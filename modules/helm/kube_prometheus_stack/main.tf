resource "kubectl_manifest" "namespace" {
  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Namespace"
    metadata = {
      name = var.namespace
      labels = {
        name = var.namespace
      }
    }
  })

  wait_for {
    field {
      key   = "status.phase"
      value = "Active"
    }
  }
}

# Grafana reads its administrator credentials from a secret rather than from a
# value rendered into the release, so that the password does not sit in the Helm
# release metadata in the cluster.
resource "kubectl_manifest" "grafana_admin" {
  depends_on = [kubectl_manifest.namespace]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Secret"
    metadata = {
      name      = local.admin_secret_name
      namespace = var.namespace
    }
    type = "Opaque"
    stringData = {
      "admin-user"     = var.admin_user
      "admin-password" = var.admin_password
    }
  })

  sensitive_fields = ["stringData.admin-password"]
}

locals {
  admin_secret_name = "grafana-admin"

  # Same rate limiting and allow list shape as the other exposed service. A
  # dashboard carries a good deal of information about the cluster, so it is worth
  # gating even in a lab.
  ingress_annotations = merge(
    {
      "cert-manager.io/cluster-issuer" = var.certificate_issuer
    },
    length(var.allow_list) == 0 ? {} : {
      "haproxy.org/allow-list" = join(",", var.allow_list)
    }
  )

  values = {
    # Node exporter is deliberately absent from this map: it is a daemonset and has
    # to run on every node, GPU nodes included, which is where the disk and network
    # series the hardware dashboard draws come from.
    grafana = {
      nodeSelector = var.node_selector

      admin = {
        existingSecret = local.admin_secret_name
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }

      # The sidecar watches for ConfigMaps carrying the grafana_dashboard label and
      # loads what it finds, which is how the dashboards below reach Grafana without
      # being baked into the release.
      sidecar = {
        dashboards = {
          enabled          = true
          label            = "grafana_dashboard"
          labelValue       = "1"
          searchNamespace  = var.namespace
          folderAnnotation = "grafana_folder"
          provider = {
            foldersFromFilesStructure = true
          }
        }
      }

      ingress = {
        enabled          = true
        ingressClassName = var.ingress_class
        hosts            = [var.fqdn]
        path             = "/"
        pathType         = "Prefix"
        annotations      = local.ingress_annotations
        tls = [{
          secretName = "grafana-tls"
          hosts      = [var.fqdn]
        }]
      }
    }

    prometheus = {
      prometheusSpec = {
        nodeSelector = var.node_selector
        retention    = var.retention

        # Out of the box the operator only adopts monitors carrying the release
        # label of the chart. The two below are written by hand and are not part of
        # the release, so the selectors are opened up rather than the monitors being
        # labelled to look like something they are not.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false

        storageSpec = {
          volumeClaimTemplate = {
            spec = merge(
              {
                accessModes = ["ReadWriteOnce"]
                resources = {
                  requests = {
                    storage = var.storage_size
                  }
                }
              },
              var.storage_class == "" ? {} : { storageClassName = var.storage_class }
            )
          }
        }
      }
    }

    alertmanager = {
      alertmanagerSpec = {
        nodeSelector = var.node_selector
      }
    }

    prometheusOperator = {
      nodeSelector = var.node_selector
      admissionWebhooks = {
        patch = {
          nodeSelector = var.node_selector
        }
      }
    }

    kube-state-metrics = {
      nodeSelector = var.node_selector
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  depends_on = [
    kubectl_manifest.namespace,
    kubectl_manifest.grafana_admin,
  ]

  name      = "kube-prometheus-stack"
  namespace = var.namespace

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.chart_version

  # The chart installs a large set of CRDs and waits on a webhook, which takes a
  # while on a cluster that has not seen it before.
  timeout = 900
  wait    = true

  values = [yamlencode(local.values)]
}

# GPU telemetry. The GPU operator already runs the DCGM exporter as a daemonset on
# every GPU node and puts a service in front of it; all that is missing is telling
# Prometheus to scrape it.
resource "kubectl_manifest" "dcgm_service_monitor" {
  depends_on = [helm_release.kube_prometheus_stack]

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "nvidia-dcgm-exporter"
      namespace = var.namespace
    }
    spec = {
      namespaceSelector = {
        matchNames = [var.gpu_operator_namespace]
      }
      selector = {
        matchLabels = {
          app = "nvidia-dcgm-exporter"
        }
      }
      endpoints = [{
        port     = "gpu-metrics"
        interval = "15s"
        # DCGM reports per GPU rather than per pod, and the exporter names the node
        # in every sample, so the pod it happened to be scraped from is noise.
        relabelings = [{
          sourceLabels = ["__meta_kubernetes_pod_node_name"]
          targetLabel  = "node"
          action       = "replace"
        }]
      }]
    }
  })
}

# The model pods serve their metrics on the same port as the API, and KubeAI does
# not put a service in front of them: it routes through its own proxy. A headless
# service is added here purely so that there is something for a ServiceMonitor to
# select, which keeps the scrape configuration in the same shape as the one above.
resource "kubectl_manifest" "vllm_metrics_service" {
  depends_on = [helm_release.kube_prometheus_stack]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "Service"
    metadata = {
      name      = "vllm-metrics"
      namespace = var.model_namespace
      labels = {
        "app.kubernetes.io/name" = "vllm-metrics"
      }
    }
    spec = {
      clusterIP = "None"
      selector = {
        "app.kubernetes.io/managed-by" = "kubeai"
        "app.kubernetes.io/name"       = "vllm"
      }
      ports = [{
        name       = "http"
        port       = 8000
        targetPort = 8000
        protocol   = "TCP"
      }]
    }
  })
}

resource "kubectl_manifest" "vllm_service_monitor" {
  depends_on = [kubectl_manifest.vllm_metrics_service]

  yaml_body = yamlencode({
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "vllm"
      namespace = var.namespace
    }
    spec = {
      namespaceSelector = {
        matchNames = [var.model_namespace]
      }
      selector = {
        matchLabels = {
          "app.kubernetes.io/name" = "vllm-metrics"
        }
      }
      endpoints = [{
        port     = "http"
        path     = "/metrics"
        interval = "15s"
        # Which model produced a sample matters more than which pod did, and a pod
        # name changes on every scale up.
        relabelings = [
          {
            sourceLabels = ["__meta_kubernetes_pod_label_kubeai_org_model"]
            targetLabel  = "model_name"
            action       = "replace"
          },
          {
            sourceLabels = ["__meta_kubernetes_pod_node_name"]
            targetLabel  = "node"
            action       = "replace"
          },
        ]
      }]
    }
  })
}

# One ConfigMap per dashboard document. The file name comes from the filesystem, so
# the for_each keys are known at plan time, and the label is what the Grafana
# sidecar watches for.
resource "kubectl_manifest" "dashboards" {
  for_each   = var.dashboards_path != "" ? fileset(var.dashboards_path, "*.json") : toset([])
  depends_on = [helm_release.kube_prometheus_stack]

  yaml_body = yamlencode({
    apiVersion = "v1"
    kind       = "ConfigMap"
    metadata = {
      name      = "grafana-dashboard-${replace(each.value, ".json", "")}"
      namespace = var.namespace
      labels = {
        grafana_dashboard = "1"
      }
      annotations = {
        grafana_folder = "GPU"
      }
    }
    data = {
      (each.value) = file("${var.dashboards_path}/${each.value}")
    }
  })
}

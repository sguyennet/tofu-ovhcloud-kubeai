locals {
  # The trusted networks are a comma-delimited list and commas separate arguments
  # in a helm set expression, hence values rather than set entries here.
  proxy_protocol_config = length(var.proxy_protocol_trusted_cidrs) == 0 ? {} : {
    "proxy-protocol" = join(", ", var.proxy_protocol_trusted_cidrs)
  }

  proxy_protocol_annotations = length(var.proxy_protocol_trusted_cidrs) == 0 ? {} : {
    # MKS 1.31 and above. Older clusters use
    # service.beta.kubernetes.io/ovh-loadbalancer-proxy-protocol.
    "loadbalancer.openstack.org/proxy-protocol" = "v2"
  }

  chart_values = {
    controller = {
      config = local.proxy_protocol_config

      # Dropping the UDP port is not enough on its own: without the argument the
      # controller keeps advertising alt-svc and browsers keep chasing it.
      extraArgs = var.quic ? [] : ["--disable-quic"]

      service = {
        annotations = local.proxy_protocol_annotations
        enablePorts = var.quic ? {} : { quic = false }
      }
    }
  }
}

resource "helm_release" "haproxy-ingress" {
  name      = "haproxy-ingress"
  namespace = var.namespace

  repository = "https://haproxytech.github.io/helm-charts"
  chart      = "kubernetes-ingress"
  version    = var.chart_version

  create_namespace = true

  timeout = 900
  wait    = true

  values = [yamlencode(local.chart_values)]

  set = concat([
    {
      name  = "controller.kind"
      type  = "string"
      value = "Deployment"
    },
    {
      name  = "controller.replicaCount"
      type  = "auto"
      value = var.replica_count
    },
    {
      name  = "controller.ingressClassResource.name"
      type  = "string"
      value = var.ingress_class
    },
    {
      name  = "controller.ingressClassResource.default"
      type  = "auto"
      value = var.default_ingress_class
    },
    {
      name  = "controller.ingressClass"
      type  = "string"
      value = var.ingress_class
    },
    # Publish the load balancer address in the status of every Ingress object,
    # this is what ExternalDNS reads to create the DNS records.
    {
      name  = "controller.publishService.enabled"
      type  = "auto"
      value = "true"
    },
    {
      name  = "controller.service.type"
      type  = "string"
      value = "LoadBalancer"
    },
    {
      name  = "controller.service.externalTrafficPolicy"
      type  = "string"
      value = var.external_traffic_policy
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/openstack-internal-load-balancer"
      type  = "string"
      value = var.private
    },
    # ConfigMap entries have to stay strings.
    {
      name  = "controller.config.ssl-redirect"
      type  = "string"
      value = var.ssl_redirect
    }
    ],
    # Pin the controller and the CRD job to the selected nodes.
    flatten([for key, value in var.node_selector : [
      {
        name  = "controller.nodeSelector.${replace(key, ".", "\\.")}"
        type  = "string"
        value = value
      },
      {
        name  = "crdjob.nodeSelector.${replace(key, ".", "\\.")}"
        type  = "string"
        value = value
      }
    ]])
  )
}

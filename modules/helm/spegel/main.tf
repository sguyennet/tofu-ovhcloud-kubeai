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

locals {
  # Every node runs the mirror and serves the layers it already holds to the
  # others, so a pull only leaves the cluster the first time an image is needed.
  # It only works if containerd is told to read its per registry configuration
  # from a directory, which is where the mirror writes itself in.
  #
  # MKS does not set that path, and the file it does ship is not ours to edit.
  # What it does do is import anything dropped in conf.d, which is enough to add
  # the settings that are missing. Containerd then reads the directory on every
  # pull, so a mirror appearing later needs no further restart.
  #
  # The same file raises the two limits that bound a pull once the layers come
  # from a peer rather than from the far side of the internet. Three concurrent
  # downloads and, above all, one concurrent unpack: the four large layers of a
  # vLLM image are decompressed one after the other, and that is what the pull
  # ends up waiting on.
  #
  # Containerd refuses to start on a configuration it cannot parse, which on a
  # file written into a running node would mean a node that never comes back, so
  # the merged configuration is read back before anything is restarted.
  containerd_script = <<-EOT
    set -eu

    dropin_dir=/host/etc/containerd/conf.d
    dropin=$dropin_dir/spegel-registry.toml

    mkdir -p "$dropin_dir" /host/etc/containerd/certs.d

    cat > /tmp/wanted <<'TOML'
    version = 3

    [plugins."io.containerd.cri.v1.images"]
      max_concurrent_downloads = ${var.max_concurrent_downloads}
      concurrent_layer_fetch_buffer = ${var.concurrent_layer_fetch_buffer}

    [plugins."io.containerd.cri.v1.images".registry]
      config_path = "/etc/containerd/certs.d"

    [plugins."io.containerd.transfer.v1.local"]
      max_concurrent_downloads = ${var.max_concurrent_downloads}
      max_concurrent_unpacks = ${var.max_concurrent_unpacks}
      concurrent_layer_fetch_buffer = ${var.concurrent_layer_fetch_buffer}
    TOML

    if cmp -s /tmp/wanted "$dropin"; then
      echo "containerd already reads /etc/containerd/certs.d, nothing to do"
    else
      cp /tmp/wanted "$dropin"

      if ! chroot /host containerd config dump >/dev/null 2>&1; then
        echo "containerd rejects the merged configuration, taking the file back out" >&2
        rm -f "$dropin"
        exit 1
      fi

      echo "wrote $dropin, restarting containerd"
      chroot /host systemctl restart containerd
      echo "containerd restarted"
    fi

    # A pod of a daemon set is expected to stay alive. There is nothing left to
    # do on this node, the point of staying is to be scheduled again, and write
    # the file again, on whichever node replaces it.
    while true; do
      sleep 3600
    done
  EOT
}

# Restarting containerd does not stop the containers already running on the node,
# their shims are separate processes, but the kubelet loses its connection to the
# runtime for a moment. It happens once per node, when the file is first written.
resource "kubectl_manifest" "containerd_registry_config" {
  count      = var.configure_containerd ? 1 : 0
  depends_on = [kubectl_manifest.namespace]

  yaml_body = yamlencode({
    apiVersion = "apps/v1"
    kind       = "DaemonSet"
    metadata = {
      name      = "spegel-containerd-config"
      namespace = var.namespace
    }
    spec = {
      selector = {
        matchLabels = {
          app = "spegel-containerd-config"
        }
      }
      template = {
        metadata = {
          labels = {
            app = "spegel-containerd-config"
          }
        }
        spec = {
          # The configuration of a node is written from the node itself, in its
          # own root, and telling systemd to restart a service needs to reach it
          # as the host rather than as a container.
          hostPID                      = true
          automountServiceAccountToken = false
          tolerations                  = local.tolerations
          priorityClassName            = "system-node-critical"

          containers = [{
            name    = "config"
            image   = var.containerd_config_image
            command = ["/bin/sh", "-c", local.containerd_script]

            securityContext = {
              privileged = true
            }

            volumeMounts = [{
              name      = "host"
              mountPath = "/host"
            }]

            resources = {
              requests = {
                cpu    = "10m"
                memory = "16Mi"
              }
              limits = {
                cpu    = "100m"
                memory = "64Mi"
              }
            }
          }]

          volumes = [{
            name = "host"
            hostPath = {
              path = "/"
              type = "Directory"
            }
          }]
        }
      }
    }
  })
}

locals {
  # An operator of Exists carries no value, and a null one is not something the
  # API accepts, so the empty keys are dropped rather than rendered.
  tolerations = [for toleration in var.tolerations : {
    for key, value in toleration : key => value if value != null
  }]
}

resource "helm_release" "spegel" {
  depends_on = [kubectl_manifest.namespace, kubectl_manifest.containerd_registry_config]

  name      = "spegel"
  namespace = var.namespace

  repository = "oci://ghcr.io/spegel-org/helm-charts"
  chart      = "spegel"
  version    = var.chart_version

  timeout = 600
  wait    = true

  values = [yamlencode({
    spegel = {
      mirroredRegistries = var.mirrored_registries
    }

    # The mirror belongs on every node that pulls an image, the GPU nodes above
    # all, and those are tainted.
    tolerations = local.tolerations
  })]
}

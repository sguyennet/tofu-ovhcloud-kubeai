locals {
  # A precompiled image is published per major version, and the operator builds the
  # tag by appending the kernel of the node to whatever version it is given: 595
  # becomes 595-5.15.0-185-generic-ubuntu22.04. A full version would name a tag
  # that was never published, so it is cut back to its major here rather than
  # refused, which lets the same value stand on both sides of a switch of
  # use_precompiled_driver. Compiling from source wants the full version and gets
  # it untouched.
  driver_version = (
    var.use_precompiled_driver && var.driver_version != ""
    ? regex("^[0-9]+", var.driver_version)
    : var.driver_version
  )
}

# The operator installs the NVIDIA driver, the container toolkit, the device plugin
# and GPU Feature Discovery, which labels the GPU nodes with nvidia.com/gpu.* .
# Those labels are what the KubeAI resource profiles select on.
resource "helm_release" "gpu-operator" {
  name      = "gpu-operator"
  namespace = var.namespace

  repository = "https://helm.ngc.nvidia.com/nvidia"
  chart      = "gpu-operator"
  version    = var.chart_version

  create_namespace = true

  # Building and loading the driver on the GPU nodes takes a while.
  timeout = 1800
  wait    = true

  set = concat(
    [{
      # Picks the image NVIDIA built for the kernel of the node instead of
      # building the module there. See use_precompiled_driver for the trade.
      name  = "driver.usePrecompiled"
      value = tostring(var.use_precompiled_driver)
    }],
    # The chart's sixty second initial delay is sized for a driver built on the
    # node. With a precompiled module the driver logs "Done, now waiting for
    # signal" around twelve seconds in and then waits out the rest of the delay,
    # which the device plugin, GPU Feature Discovery and the pending model pod all
    # sit behind. Probing sooner and more often is what turns that dead time back
    # into a shorter scale-up.
    [
      {
        name  = "driver.startupProbe.initialDelaySeconds"
        value = tostring(var.driver_startup_probe_initial_delay)
      },
      {
        name  = "driver.startupProbe.periodSeconds"
        value = tostring(var.driver_startup_probe_period)
      },
      {
        name  = "driver.startupProbe.failureThreshold"
        value = tostring(var.driver_startup_probe_failure_threshold)
      },
    ],
    var.driver_version != "" ? [{
      name = "driver.version"
      # Typed, so that a major on its own is sent as "595" rather than coerced to
      # a number and rendered as 595 without quotes.
      type  = "string"
      value = local.driver_version
    }] : [],
    # Keep the control components away from the GPU nodes. The operands
    # (driver, toolkit, device plugin, GFD, DCGM) and the node feature discovery
    # worker are deliberately left alone, they are daemonsets targeting the GPU
    # nodes and they already tolerate the nvidia.com/gpu taint.
    flatten([for key, value in var.node_selector : [
      {
        name  = "operator.nodeSelector.${replace(key, ".", "\\.")}"
        type  = "string"
        value = value
      },
      {
        name  = "node-feature-discovery.master.nodeSelector.${replace(key, ".", "\\.")}"
        type  = "string"
        value = value
      },
      {
        name  = "node-feature-discovery.gc.nodeSelector.${replace(key, ".", "\\.")}"
        type  = "string"
        value = value
      }
    ]])
  )
}

variable "chart_version" {
  description = "nvidia/gpu-operator chart version"
  type        = string
  default     = "v26.7.0"
}

variable "namespace" {
  description = "Namespace where the GPU operator is deployed"
  type        = string
  default     = "gpu-operator"
}

variable "driver_version" {
  description = "NVIDIA driver version installed by the operator. Empty means the chart default. Compiled from source it is the full version, 595.91.07. A precompiled driver is published per major version, and the value is cut back to its major on the way through, so either form does: 595 and 595.91.07 both land on 595-5.15.0-185-generic-ubuntu22.04."
  type        = string
  default     = ""

  validation {
    # Anything with a major in it can be cut down to one. Nothing at all cannot,
    # and the chart default is a full version, which the precompiled path has no
    # published tag for.
    condition     = !var.use_precompiled_driver || can(regex("^[0-9]+", var.driver_version))
    error_message = "A precompiled driver is published per major version, so driver_version cannot be left empty when use_precompiled_driver is set: give the major, 595, or a full version to be cut down, 595.91.07."
  }
}

variable "use_precompiled_driver" {
  description = "Load a kernel module NVIDIA has already built for the kernel of the node, rather than compiling one on the node at every start. Compiling costs close to two minutes on each new node, installing kernel headers included, and is the largest part of the wait before a GPU can be scheduled on. The catch is the coupling: NVIDIA publishes an image per kernel, so a node image carrying a kernel it has not built for leaves the driver unable to start."
  type        = bool
  default     = true
}

variable "driver_startup_probe_initial_delay" {
  description = "Seconds the operator waits before probing the driver container for the first time. The chart waits 60, which is sized for a driver compiled on the node: with a precompiled module the driver has loaded and is idle after about twelve seconds, so the rest is dead time on every new node. Lower it and the node advertises its GPU sooner."
  type        = number
  default     = 10
}

variable "driver_startup_probe_period" {
  description = "Seconds between driver startup probes. Multiplied by the failure threshold this is how long a driver is given before the operator gives up, so shortening the period shortens that budget too, and the threshold below is raised to hold it."
  type        = number
  default     = 5
}

variable "driver_startup_probe_failure_threshold" {
  description = "Consecutive failed startup probes before the driver container is restarted. The default of 120 at the chart's ten second period allows twenty minutes; keep the product in that range so that a node compiling from source, or one waiting on kernel headers, is still given room."
  type        = number
  default     = 240

  validation {
    # The budget a driver is given before its container is restarted is this
    # threshold multiplied by the period. Shortening the period without raising the
    # threshold shrinks that budget silently, and it only shows up on a node slow
    # enough to have needed it.
    condition     = var.driver_startup_probe_failure_threshold * var.driver_startup_probe_period >= 600
    error_message = "The driver startup probe budget, the failure threshold times the period, is under ten minutes. A node compiling the driver from source, or waiting on kernel headers, can need longer."
  }
}

variable "node_selector" {
  description = "Node labels the operator control components are pinned to: the operator itself, the node feature discovery master and its garbage collector. The operands and the node feature discovery worker are not concerned, they have to run on the GPU nodes."
  type        = map(string)
  default     = {}
}

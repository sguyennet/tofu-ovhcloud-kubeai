variable "chart_version" {
  description = "spegel chart version"
  type        = string
  default     = "0.7.4"
}

variable "namespace" {
  description = "Namespace where the image mirror is deployed"
  type        = string
  default     = "spegel"
}

variable "mirrored_registries" {
  description = "Registries a pull is allowed to resolve from a peer. Empty means every registry."
  type        = list(string)

  default = [
    "https://docker.io",
    "https://ghcr.io",
    "https://quay.io",
    "https://registry.k8s.io",
    # Every image of the GPU operator comes from here, the driver among them, and
    # a node joining the pool pulls them before it can serve a model.
    "https://nvcr.io",
  ]
}

variable "tolerations" {
  description = "Tolerations of the mirror, which has to run on every node holding images. The default one matches the taint reserving the GPU nodes for the KubeAI models, where the large images land."
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))

  default = [{
    key      = "nvidia.com/gpu"
    operator = "Equal"
    value    = "present"
    effect   = "NoSchedule"
  }]
}

variable "configure_containerd" {
  description = "Install the containerd registry configuration the mirror needs. Without it the mirror runs and containerd ignores it, so this is only turned off where something else already sets config_path."
  type        = bool
  default     = true
}

variable "max_concurrent_downloads" {
  description = "Layers containerd fetches at once. The default of three is what bounds the pull of an image whose weight sits in four large layers, peers or no peers."
  type        = number
  default     = 6
}

variable "max_concurrent_unpacks" {
  description = "Layers containerd decompresses at once. The default of one serialises the gunzip of every layer, which is what a pull is left waiting on once the bytes arrive from a peer at local network speed."
  type        = number
  default     = 3
}

variable "concurrent_layer_fetch_buffer" {
  description = "Bytes buffered per layer being fetched. Zero, the containerd default, streams unbuffered. A value in the tens of megabytes lets a fetch run ahead of the unpack that consumes it, at the cost of that much memory per layer in flight."
  type        = number
  default     = 0
}

variable "containerd_config_image" {
  description = "Image of the job writing the containerd configuration. Any image with a POSIX shell does, the script only writes a file and calls systemctl in the host root."
  type        = string
  default     = "alpine:3.22"
}

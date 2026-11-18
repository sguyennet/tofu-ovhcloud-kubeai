# Global

variable "prefix_name" {
  description = "Prefix prepended to the name of every resource"
  type        = string
  default     = "mks-kubeai"
}

variable "service_name" {
  description = "OVHcloud Public Cloud project ID"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32}$", var.service_name))
    error_message = "The service name is not a project ID"
  }
}

variable "region" {
  description = "Public Cloud region hosting the private network and the cluster"
  type        = string
  default     = "GRA11"

  validation {
    condition     = can(regex("^((BHS|DE|GRA|MUM|SBG|SPG|SYD|UK|WAW)[0-9]{1,2}|RBX-[A-Z]|EU-WEST-PAR|EU-SOUTH-MIL|CA-EAST-TOR)$", var.region))
    error_message = "The region is not valid"
  }
}

# Network

variable "private_network_vlan_id" {
  description = "vRack VLAN ID of the private network, also used to build the subnet CIDR (10.<vlan_id>.0.0/16)"
  type        = string
  default     = "1"

  validation {
    condition     = can(regex("^[0-9]{1,4}$", var.private_network_vlan_id))
    error_message = "The VLAN ID is not a number between 0 and 4096"
  }
}

variable "gateway_size" {
  description = "Size of the OVHcloud public cloud gateway (s, m, l, xl or 2xl)"
  type        = string
  default     = "s"

  validation {
    condition     = can(regex("^(s|m|l|xl|2xl)$", var.gateway_size))
    error_message = "The gateway size must be either s, m, l, xl, or 2xl"
  }
}

variable "private_network_routing_as_default" {
  description = "Route the egress traffic of the cluster nodes through their private interface, and so through the gateway, rather than through the public interface each node already carries. True gives a single, stable exit address, at the bandwidth of one gateway shared by every node. False gives each node its own public interface, which is what makes a several gigabyte image pull or a model download go at the speed of the node rather than the speed of the gateway. With the image mirror deployed, a pull that another node has already done does not leave the private network at all."
  type        = bool
  default     = true
}

# Kubernetes

variable "kubernetes_version" {
  description = "Managed Kubernetes Service version"
  type        = string
  default     = "1.34"
}

variable "kubernetes_plan" {
  description = "Managed Kubernetes Service plan (free or standard)"
  type        = string
  default     = "free"

  validation {
    condition     = can(regex("^(free|standard)$", var.kubernetes_plan))
    error_message = "The Kubernetes cluster plan must be either free or standard"
  }
}

variable "node_pools" {
  description = "Node pool parameters. The name of each pool is prefixed with prefix_name."
  type = list(object({
    name               = string
    flavor             = string
    desired_nodes      = optional(string)
    max_nodes          = string
    min_nodes          = string
    availability_zones = list(string)
    autoscale          = optional(bool, false)
    labels             = optional(map(string), {})
    taints             = optional(list(map(string)), [])
  }))

  default = [
    # Pool hosting the platform components (ingress controller, ExternalDNS,
    # cert-manager) and the regular workloads.
    {
      name               = "control-plane"
      flavor             = "b3-8"
      desired_nodes      = "3"
      max_nodes          = "5"
      min_nodes          = "0"
      availability_zones = []
    },
    # GPU pool: 2 instances, each one with a single NVIDIA L4.
    # l4-90 = 1 x L4, l4-180 = 2 x L4, l4-360 = 4 x L4.
    #
    # The taint reserves those nodes for the KubeAI models. Do not change its key,
    # value or effect: the tolerations of the KubeAI resource profiles, of the GPU
    # operator operands and of the node feature discovery worker all match exactly
    # "nvidia.com/gpu=present:NoSchedule".
    {
      name               = "compute-gpu"
      flavor             = "l4-90"
      autoscale          = true
      min_nodes          = "0"
      max_nodes          = "6"
      availability_zones = []

      # These two labels are also set by GPU Feature Discovery once a node is up.
      # Declaring them on the pool is what lets the cluster autoscaler grow the
      # pool from zero: it simulates a node out of this template, and the KubeAI
      # resource profile of the models selects on exactly these labels. Keep them
      # in sync with the flavor above.
      labels = {
        "nvidia.com/gpu.family"            = "ada-lovelace"
        "nvidia.com/gpu.memory"            = "23034"
        "node.kubernetes.ovhcloud.com/gpu" = "l4-90"
      }

      taints = [{
        key    = "nvidia.com/gpu"
        value  = "present"
        effect = "NoSchedule"
      }]
    }
  ]
}

variable "platform_node_pool" {
  description = "Name of the node pool (as declared in node_pools, without the prefix) running the platform components: ingress controller, ExternalDNS and cert-manager"
  type        = string
  default     = "control-plane"

  validation {
    condition     = contains(var.node_pools[*].name, var.platform_node_pool)
    error_message = "The platform node pool must be one of the pools declared in node_pools"
  }
}

# Ingress

variable "ingress_private" {
  description = "Expose the HAProxy ingress controller through an internal (private network) load balancer instead of a public one"
  type        = string
  default     = "false"

  validation {
    condition     = can(regex("^(true|false)$", var.ingress_private))
    error_message = "Ingress private is a bool. Value have to be true or false."
  }
}



variable "ingress_proxy_protocol" {
  description = "Carry the real client IP from the OVHcloud load balancer to the ingress controller with the PROXY protocol. Without it the controller sees the address of the load balancer for every request, and an allow list built from client addresses matches nothing."
  type        = bool
  default     = true
}

variable "ingress_quic" {
  description = "Serve HTTP/3 over QUIC on the ingress controller. Off because UDP through the OVHcloud load balancer cannot carry the PROXY protocol: the advertised HTTP/3 endpoint is unreachable, and browsers pay a timeout on it before falling back to TCP."
  type        = bool
  default     = false
}

variable "ingress_replica_count" {
  description = "Number of HAProxy ingress controller replicas"
  type        = string
  default     = "2"
}

# DNS and certificates

variable "ovh_dns_domain" {
  description = "OVHcloud DNS zone managed by ExternalDNS and used to solve the ACME DNS-01 challenges"
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]+\\.(.+)", var.ovh_dns_domain))
    error_message = "The DNS domain is not valid"
  }
}

variable "external_dns_policy" {
  description = "ExternalDNS synchronization policy (sync, upsert-only or create-only)"
  type        = string
  default     = "sync"

  validation {
    condition     = can(regex("^(sync|upsert-only|create-only)$", var.external_dns_policy))
    error_message = "The policy must be either sync, upsert-only or create-only"
  }
}

variable "certificate_issuer" {
  description = "cert-manager ClusterIssuer signing the Open WebUI certificate"
  type        = string
  default     = "letsencrypt-production"

  validation {
    condition     = can(regex("^letsencrypt-(production|staging)$", var.certificate_issuer))
    error_message = "The certificate issuer must be either letsencrypt-production or letsencrypt-staging"
  }
}

variable "acme_email" {
  description = "Email address registered on the Let's Encrypt account"
  type        = string
}

variable "ovh_api_endpoint" {
  description = "OVHcloud API endpoint"
  type        = string
  default     = "ovh-eu"

  validation {
    condition     = can(regex("^(ovh-eu|ovh-ca|ovh-us)$", var.ovh_api_endpoint))
    error_message = "The OVHcloud API endpoint must be either ovh-eu, ovh-ca or ovh-us"
  }
}

variable "ovh_api_dns_application_key" {
  description = "OVHcloud API application key allowed to manage the DNS zone"
  type        = string
}

variable "ovh_api_dns_application_secret" {
  description = "OVHcloud API application secret allowed to manage the DNS zone"
  type        = string
  sensitive   = true
}

variable "ovh_api_dns_consumer_key" {
  description = "OVHcloud API consumer key allowed to manage the DNS zone"
  type        = string
  sensitive   = true
}

# GPU operator

variable "gpu_operator_driver_version" {
  description = "NVIDIA driver version installed by the GPU operator. With gpu_operator_use_precompiled_driver, the major version alone, which the operator completes with the kernel of the node: 595 becomes 595-5.15.0-185-generic-ubuntu22.04. Without it, the full version, or empty for the chart default."
  type        = string
  default     = "595.71.05"
}

variable "gpu_operator_use_precompiled_driver" {
  description = "Load a kernel module NVIDIA has already built for the kernel of the node. It removes the two minutes a new node spends compiling one, and ties the pool to the kernels NVIDIA publishes for: a node image moving to a kernel they have not built leaves the driver unable to start, and the way back is this variable."
  type        = bool
  default     = true
}

variable "gpu_operator_chart_version" {
  description = "Version of the NVIDIA GPU operator Helm chart"
  type        = string
  default     = "v26.7.0"
}

variable "gpu_operator_driver_startup_probe_initial_delay" {
  description = "Seconds the operator waits before probing the driver container for the first time. The chart waits 60, a value sized for a driver compiled on the node: with a precompiled module the driver has loaded and is idle after about twelve seconds, and the container toolkit, the device plugin and every pod waiting on the GPU sit behind the rest of that delay."
  type        = number
  default     = 10
}

variable "gpu_operator_driver_startup_probe_period" {
  description = "Seconds between driver startup probes. Multiplied by the failure threshold this is the time a driver is given before its container is restarted, so shortening the period shortens that budget unless the threshold is raised to match."
  type        = number
  default     = 5
}

variable "gpu_operator_driver_startup_probe_failure_threshold" {
  description = "Consecutive failed startup probes before the driver container is restarted. The chart allows twenty minutes, 120 probes at its ten second period; keep the product of this and the period in that range so that a node compiling from source, or one waiting on kernel headers, is still given room."
  type        = number
  default     = 240
}

# Image mirror

variable "spegel_enabled" {
  description = "Deploy the image mirror. It lets a node take the layers of an image from a peer over the private network rather than from the registry, which is what turns the first pull of the fourteen gigabyte vLLM image on a new node from around eleven minutes into around two and a half. False removes it entirely, and every new node then pulls from the registry."
  type        = bool
  default     = true
}

variable "spegel_configure_containerd" {
  description = "Let the image mirror install the containerd settings it needs, which are written on every node and cost one restart of containerd there. False deploys the mirror without touching the nodes, where containerd then ignores it."
  type        = bool
  default     = true
}

variable "spegel_mirrored_registries" {
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

variable "spegel_max_concurrent_downloads" {
  description = "Layers containerd fetches at once. Three, its default, is what bounds the pull of an image whose weight sits in a handful of large layers, peers or no peers."
  type        = number
  default     = 6

  validation {
    condition     = var.spegel_max_concurrent_downloads >= 1
    error_message = "At least one layer has to be downloadable at a time"
  }
}

variable "spegel_max_concurrent_unpacks" {
  description = "Layers containerd decompresses at once. One, its default, serialises the gunzip of every layer, which is what a pull is left waiting on once the bytes arrive from a peer at local network speed."
  type        = number
  default     = 3

  validation {
    condition     = var.spegel_max_concurrent_unpacks >= 1
    error_message = "At least one layer has to be unpackable at a time"
  }
}

variable "spegel_concurrent_layer_fetch_buffer" {
  description = "Bytes buffered per layer being fetched. Zero, the containerd default, streams unbuffered. A value in the tens of megabytes lets a fetch run ahead of the unpack that consumes it, at the cost of that much memory per layer in flight."
  type        = number
  default     = 0

  validation {
    condition     = var.spegel_concurrent_layer_fetch_buffer >= 0
    error_message = "The buffer cannot be negative"
  }
}

# Monitoring

variable "monitoring_enabled" {
  description = "Deploy the monitoring stack: Prometheus, Alertmanager, Grafana, node exporter and kube-state-metrics, with the GPU telemetry the operator already exports and the metrics the model servers already serve. False deploys none of it."
  type        = bool
  default     = true
}

variable "monitoring_subdomain" {
  description = "Subdomain of ovh_dns_domain serving Grafana"
  type        = string
  default     = "monitoring-ai"
}

variable "monitoring_chart_version" {
  description = "kube-prometheus-stack chart version"
  type        = string
  default     = "89.2.4"
}

variable "monitoring_admin_user" {
  description = "Login of the Grafana administrator. Grafana treats this as a username rather than an address, so an address works but is not verified or mailed to."
  type        = string
}

variable "monitoring_admin_password" {
  description = "Password of the Grafana admin account. Grafana writes the administrator into its database on first start, so a later change to this value does not reach an existing installation: rotate it in Grafana instead."
  type        = string
  sensitive   = true
}

variable "monitoring_retention" {
  description = "How long Prometheus keeps samples"
  type        = string
  default     = "15d"
}

variable "monitoring_storage_size" {
  description = "Size of the volume holding the Prometheus time series database"
  type        = string
  default     = "50Gi"
}

variable "monitoring_allow_list" {
  description = "Addresses and CIDRs allowed to reach Grafana. Empty means any address, and the dashboards describe the cluster in some detail."
  type        = list(string)
  default     = []
}

variable "monitoring_dashboards_path" {
  description = "Directory, relative to the configuration, holding the Grafana dashboard documents to load"
  type        = string
  default     = "manifests/grafana-dashboards"
}

# Valkey

variable "valkey_version" {
  description = "Valkey version of the managed cluster: 8.1 or 9.1"
  type        = string
  default     = "8.1"

  validation {
    condition     = contains(["8.1", "9.1"], var.valkey_version)
    error_message = "The Valkey version must be 8.1 or 9.1"
  }
}

variable "valkey_plan" {
  description = "Service plan of the managed Valkey cluster: essential runs a single node, production a pair with an SLA"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["discovery", "production"], var.valkey_plan)
    error_message = "The plan must be essential, discovery, business or production. Valkey is not offered on the enterprise plan."
  }
}

variable "valkey_flavor" {
  description = "Node flavor of the managed Valkey cluster. Open WebUI only stores its configuration and its sessions there, so the smallest flavor of the plan is enough."
  type        = string
  default     = "b3-8"

  validation {
    condition     = can(regex("^(b|db)[0-9]-[0-9]{1,3}$", var.valkey_flavor))
    error_message = "The flavor is not valid"
  }
}

# PostgreSQL

variable "postgresql_version" {
  description = "PostgreSQL major version of the managed cluster"
  type        = string
  default     = "17"

  validation {
    condition     = can(regex("^[0-9]{2}$", var.postgresql_version))
    error_message = "The PostgreSQL version is a major version, for example 17"
  }
}

variable "postgresql_plan" {
  description = "Service plan of the managed PostgreSQL cluster: discovery runs a single node, production a pair with an SLA"
  type        = string
  default     = "production"

  validation {
    condition     = contains(["essential", "discovery", "business", "production", "enterprise", "advanced"], var.postgresql_plan)
    error_message = "The plan must be essential, discovery, business, production, enterprise or advanced"
  }
}

variable "postgresql_flavor" {
  description = "Node flavor of the managed PostgreSQL cluster"
  type        = string
  default     = "b3-8"

  validation {
    condition     = can(regex("^(b|db)[0-9]-[0-9]{1,3}$", var.postgresql_flavor))
    error_message = "The flavor is not valid"
  }
}

# KubeAI and Open WebUI

variable "huggingface_token" {
  description = "Hugging Face token used by KubeAI to download models. Set it through TF_VAR_huggingface_token, do not commit it."
  type        = string
  default     = ""
  sensitive   = true
}

variable "open_webui_subdomain" {
  description = "Subdomain of ovh_dns_domain exposing Open WebUI"
  type        = string
  default     = "kubeai"
}

variable "open_webui_admin_email" {
  description = "Email address of the Open WebUI admin account"
  type        = string
  default     = "admin@example.com"
}

variable "open_webui_admin_password" {
  description = "Password of the Open WebUI admin account"
  type        = string
  default     = "OVHcloud123!"
  sensitive   = true
}

variable "open_webui_enable_signup" {
  description = "Let people register themselves on Open WebUI"
  type        = string
  default     = "True"

  validation {
    condition     = can(regex("^(True|False)$", var.open_webui_enable_signup))
    error_message = "Enable signup is a bool. Value have to be True or False."
  }
}

variable "open_webui_default_user_role" {
  description = "Role given to a freshly registered Open WebUI user. pending means an administrator has to activate the account before it can be used."
  type        = string
  default     = "pending"

  validation {
    condition     = can(regex("^(pending|user|admin)$", var.open_webui_default_user_role))
    error_message = "The default user role must be either pending, user or admin"
  }
}

variable "open_webui_replica_count" {
  description = "Number of Open WebUI pods. One is the safe value for a first apply: the schema migration runs as the application starts and takes no lock, so a single pod is what guarantees nothing else is migrating beside it. The shared state a second pod needs, a PostgreSQL cluster, an Object Storage bucket, a Valkey cluster and a common secret key, is deployed either way, so scaling up afterwards is a change of this value and nothing else."
  type        = number
  default     = 1

  validation {
    condition     = var.open_webui_replica_count >= 1
    error_message = "There has to be at least one Open WebUI pod"
  }
}

variable "open_webui_public_models" {
  description = "Let every Open WebUI user reach every model. False keeps the access control of Open WebUI, which only shows a model to an administrator until the model is given an entry and a public access grant in Workspace, Models."
  type        = string
  default     = "True"

  validation {
    condition     = can(regex("^(True|False)$", var.open_webui_public_models))
    error_message = "Public models is a bool. Value have to be True or False."
  }
}

variable "open_webui_allow_list" {
  description = "IP addresses and CIDR ranges allowed to reach Open WebUI, for example [\"203.0.113.4/32\"]. Gates the web interface as much as the API, so it closes self registration to anyone outside the list. Empty means any address."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for entry in var.open_webui_allow_list : trimspace(entry) != ""])
    error_message = "The allow list must not contain an empty entry. Use [] to allow every address: an empty string renders an allow list that matches nothing and returns 403 to everyone."
  }

  validation {
    condition     = length(var.open_webui_allow_list) == 0 || var.ingress_proxy_protocol
    error_message = "An allow list needs ingress_proxy_protocol = true, otherwise the controller only ever sees the address of the load balancer and the list matches nothing, locking everyone out."
  }
}

variable "open_webui_rate_limit_requests" {
  description = "Requests accepted per token and per window on Open WebUI, interface and OpenAI compatible API alike. Empty disables the rate limiting."
  type        = string
  default     = "600"
}

variable "open_webui_rate_limit_unauthenticated_requests" {
  description = "Requests accepted per client address and per window for traffic carrying no token: login, sign up and static assets"
  type        = string
  default     = "300"
}

variable "open_webui_rate_limit_window" {
  description = "Window both Open WebUI rate limits are measured over, for example 10s, 1m or 1h"
  type        = string
  default     = "1m"
}

variable "model_cache_enabled" {
  description = "Cache the model weights on a shared filesystem, so that they are downloaded from Hugging Face once and every replica afterwards reads them over the private network. This is what the shared filesystem service is deployed for: false declares no cache profile, drops the cacheProfile field from the model manifests, and deploys neither the CSI driver nor the share network, leaving the OpenStack credentials unnecessary. Every replica then downloads its own copy of the weights, which cost close to eight minutes for an eight billion parameter model."
  type        = bool
  default     = true
}

variable "model_cache_profile_name" {
  description = "Name of the KubeAI cache profile backed by the shared filesystem. A model manifest opts into the cache by naming it in its cacheProfile field."
  type        = string
  default     = "shared-filesystem"
}

variable "model_cache_size" {
  description = "Size of the shared volume holding the cached model weights. Size it for throughput rather than for the weights themselves: the service sells bandwidth together with capacity, and a replica reads its weights once in one long sequential pass. Measured on l4-90 nodes with an 8.5GB model, that read takes 84s on the 150Gi minimum, 65s at 200Gi and 46s at 300Gi, after which it flattens, 512Gi buying five more seconds and a terabyte none. 300Gi is where the return stops. A volume can be expanded but never reduced."
  type        = string
  default     = "300Gi"
}

# vLLM engine image

variable "vllm_image_registry" {
  description = "Registry holding the vLLM engine image, as a host with no scheme and no trailing slash, for example registry.example.com. Named separately from the image so that it can also be added to the list of registries the image mirror serves from a peer: a registry absent from that list is pulled from directly by every new node, which costs the whole benefit of the mirror. Empty means the image reference in vllm_image is already complete, which is the case for a Docker Hub one."
  type        = string
  default     = ""
}

variable "vllm_image" {
  description = "Image the vLLM engine runs from, overriding the KubeAI chart's own reference for the nvidia-gpu profile. Give it without the registry, as repository:tag, and vllm_image_registry is prepended. Empty keeps the chart default, vllm/vllm-openai. Point it at the pruned L4 image once built and pushed: see image/README.md, which explains what is removed and why. The upstream image carries 708 flashinfer kernel directories that this GPU never loads, FlashAttention 3 binaries it cannot execute, and a CUDA toolkit whose static archives nothing links at runtime. A private repository additionally needs vllm_image_registry_username and vllm_image_registry_password."
  type        = string
  default     = ""
}

variable "vllm_image_registry_username" {
  description = "Username the model pods pull the vLLM engine image with. Empty, together with the password, means the repository is public and no pull secret is created."
  type        = string
  default     = ""

  validation {
    condition     = (var.vllm_image_registry_username == "") == (var.vllm_image_registry_password == "")
    error_message = "vllm_image_registry_username and vllm_image_registry_password have to be set together, or both left empty for a public repository."
  }
}

variable "vllm_image_registry_password" {
  description = "Password or token the model pods pull the vLLM engine image with. Empty, together with the username, means the repository is public. Held in the state, like every other credential here."
  type        = string
  default     = ""
  sensitive   = true
}

variable "models_path" {
  description = "Directory, relative to the configuration, holding the KubeAI Model manifests to deploy"
  type        = string
  default     = "manifests/models"
}

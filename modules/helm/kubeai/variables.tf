variable "chart_version" {
  description = "kubeai chart version"
  type        = string
  default     = "0.23.4"
}

variable "namespace" {
  description = "Namespace where KubeAI and Open WebUI are deployed"
  type        = string
  default     = "kubeai"
}

variable "huggingface_token" {
  description = "Hugging Face token used by KubeAI to pull models. Empty means no token, gated models will not be downloadable."
  type        = string
  default     = ""
  sensitive   = true
}

variable "fqdn" {
  description = "FQDN exposing Open WebUI"
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]+\\.(.+)", var.fqdn))
    error_message = "The FQDN is not valid"
  }
}

variable "ingress_class" {
  description = "IngressClass serving the Open WebUI ingress"
  type        = string
  default     = "haproxy"
}

variable "certificate_issuer" {
  description = "cert-manager ClusterIssuer signing the Open WebUI certificate"
  type        = string
  default     = "letsencrypt-production"
}

variable "admin_email" {
  description = "Email address of the Open WebUI admin account"
  type        = string
}

variable "admin_password" {
  description = "Password of the Open WebUI admin account"
  type        = string
  sensitive   = true
}

variable "enable_signup" {
  description = "Let people register themselves on Open WebUI"
  type        = string
  default     = "True"

  validation {
    condition     = can(regex("^(True|False)$", var.enable_signup))
    error_message = "Enable signup is a bool. Value have to be True or False."
  }
}



variable "default_user_role" {
  description = "Role given to a freshly registered user: pending waits for an administrator to activate the account, user and admin are activated right away."
  type        = string
  default     = "pending"

  validation {
    condition     = can(regex("^(pending|user|admin)$", var.default_user_role))
    error_message = "The default user role must be either pending, user or admin"
  }
}

variable "show_admin_details" {
  description = "Show the name and the email address of the administrator in the interface, in particular on the screen a pending user lands on."
  type        = string
  default     = "false"

  validation {
    condition     = can(regex("^(true|false)$", var.show_admin_details))
    error_message = "Show admin details is a bool. Value have to be true or false."
  }
}

variable "node_selector" {
  description = "Node labels the KubeAI controller and Open WebUI pods are pinned to. Model pods are not concerned, they are scheduled by their resource profile."
  type        = map(string)
  default     = {}
}

variable "resource_profiles" {
  description = "KubeAI resource profiles, merged with the ones of the chart. The node selectors match the labels set by GPU Feature Discovery."
  type        = map(any)

  default = {
    nvidia-gpu-l4 = {
      nodeSelector = {
        "nvidia.com/gpu.family" = "ada-lovelace"
        "nvidia.com/gpu.memory" = "23034"
      }
    }
    nvidia-gpu-l40s = {
      nodeSelector = {
        "nvidia.com/gpu.family" = "ada-lovelace"
        "nvidia.com/gpu.memory" = "46068"
      }
    }
    nvidia-gpu-a100-40gb = {
      nodeSelector = {
        "nvidia.com/gpu.family" = "ampere"
        "nvidia.com/gpu.memory" = "40960"
      }
    }
    nvidia-gpu-a100-80gb = {
      nodeSelector = {
        "nvidia.com/gpu.family" = "ampere"
        "nvidia.com/gpu.memory" = "81920"
      }
    }
    nvidia-gpu-h100 = {
      nodeSelector = {
        "nvidia.com/gpu.family" = "hopper"
        "nvidia.com/gpu.memory" = "81920"
      }
    }
  }
}

variable "cache_profile_name" {
  description = "Name of the cache profile a model names in its cacheProfile field to have its weights cached rather than downloaded on every cold start"
  type        = string
  default     = "shared-filesystem"
}

variable "cache_storage_class" {
  description = "StorageClass backing the cache profile. It has to grant ReadWriteMany, since replicas on different nodes read the same cache. Empty declares no profile at all, and every replica downloads its own copy of the weights."
  type        = string
  default     = ""
}

variable "cache_storage_size" {
  description = "Size of the volume backing the cache profile. KubeAI asks for 10Gi when nothing is set, which the OVHcloud shared filesystem service refuses: its standard-1az share type has a floor of 150 GB."
  type        = string
  default     = "150Gi"
}

variable "models_path" {
  description = "Directory holding the KubeAI Model manifests to apply once KubeAI is running, one manifest per file. Empty means no model."
  type        = string
  default     = ""
}















variable "allow_list" {
  description = "IP addresses and CIDR ranges allowed to reach the Open WebUI FQDN. This gates the web interface as much as the API, the sign up page included, so leaving it empty is what keeps self registration open to anyone. Counting on the client address requires the PROXY protocol on the controller."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for entry in var.allow_list : trimspace(entry) != ""])
    error_message = "The allow list must not contain an empty entry. Use [] to allow every address: an empty string renders an allow list that matches nothing and returns 403 to everyone."
  }
}

variable "rate_limit_requests" {
  description = "Requests accepted per token and per rate_limit_window. One bucket per distinct token, so a browser session and the key of an editor are limited separately even though they authenticate the same FQDN. Empty disables the rate limiting entirely."
  type        = string
  default     = "600"
}

variable "rate_limit_unauthenticated_requests" {
  description = "Requests accepted per client address and per rate_limit_window for traffic carrying no token: the login and sign up pages, and the static assets. Sized for a cold page load, which costs a few dozen requests. Counted per client only while the PROXY protocol carries the client address to the controller, otherwise every visitor shares this budget."
  type        = string
  default     = "300"
}

variable "rate_limit_window" {
  description = "Window both rate limits are measured over, for example 10s, 1m or 1h"
  type        = string
  default     = "1m"
}

variable "public_models" {
  description = "Let every user reach every model, KubeAI models included. False leaves Open WebUI with its own access control, where a model that has no entry in its model table is visible to administrators only."
  type        = string
  default     = "False"

  validation {
    condition     = can(regex("^(True|False)$", var.public_models))
    error_message = "Public models is a bool. Value have to be True or False."
  }
}

variable "signup_job_image" {
  description = "Image of the job that sets the sign up switch through the Open WebUI admin API. Any image with a python3 interpreter does, the script only uses the standard library."
  type        = string
  default     = "python:3.13-alpine"
}

variable "valkey_host" {
  description = "Host of the managed Valkey cluster holding the Open WebUI configuration and carrying the websocket events between the pods"
  type        = string
  default     = ""
}

variable "valkey_port" {
  description = "Port of the managed Valkey cluster"
  type        = string
  default     = ""
}

variable "valkey_username" {
  description = "User Open WebUI authenticates as on the managed Valkey cluster"
  type        = string
  default     = "default"
}

variable "valkey_password" {
  description = "Password of the Valkey user"
  type        = string
  default     = ""
  sensitive   = true
}

variable "session_cookie" {
  description = "Name of the cookie the ingress controller inserts to keep a browser on the same Open WebUI pod. Socket.IO negotiates over HTTP long polling before it upgrades, and every request of that negotiation has to reach the pod that started it: round robin across replicas breaks it, and the symptom is a reply that only appears when the page is reloaded. The Redis websocket manager carries messages between pods but cannot repair a handshake that was split across them. Empty disables persistence, which is only safe with a single replica."
  type        = string
  default     = "openwebui-server"
}

variable "replica_count" {
  description = "Number of Open WebUI pods. More than one needs the shared state below, all of it: the PostgreSQL cluster, the Object Storage bucket, the secret key and a Valkey cluster carrying the websocket events."
  type        = number
  default     = 1

  validation {
    condition     = var.replica_count >= 1
    error_message = "There has to be at least one Open WebUI pod"
  }
}

variable "secret_key" {
  description = "Key signing the Open WebUI session tokens. It has to be the same on every pod, otherwise each of them rejects the tokens issued by the others."
  type        = string
  sensitive   = true
}

variable "postgres_host" {
  description = "Host of the managed PostgreSQL cluster holding the accounts, the conversations and, through pgvector, the embeddings"
  type        = string
}

variable "postgres_port" {
  description = "Port of the managed PostgreSQL cluster"
  type        = string
}

variable "postgres_username" {
  description = "User Open WebUI authenticates as on the PostgreSQL cluster"
  type        = string
}

variable "postgres_password" {
  description = "Password of the PostgreSQL user"
  type        = string
  sensitive   = true
}

variable "postgres_database" {
  description = "Database Open WebUI uses on the PostgreSQL cluster"
  type        = string
}

variable "s3_endpoint_url" {
  description = "S3 endpoint of the bucket holding the uploaded files and the generated images"
  type        = string
}

variable "s3_region" {
  description = "Region of the bucket, as the S3 API names it"
  type        = string
}

variable "s3_bucket" {
  description = "Name of the bucket"
  type        = string
}

variable "s3_access_key_id" {
  description = "S3 access key ID reaching the bucket"
  type        = string
  sensitive   = true
}

variable "s3_secret_access_key" {
  description = "S3 secret access key reaching the bucket"
  type        = string
  sensitive   = true
}

# vLLM engine image

variable "vllm_image" {
  description = "Image the vLLM engine runs from, overriding the chart's own reference. Empty keeps the chart default."
  type        = string
  default     = ""
}

variable "registry_host" {
  description = "Key the pull secret is filed under: the registry host for a private registry, or the Docker Hub auths URL. Unused when the repository is public."
  type        = string
  default     = ""
}

variable "registry_username" {
  description = "Username the model pods pull the engine image with. Empty means the repository is public and no pull secret is created."
  type        = string
  default     = ""
}

variable "registry_password" {
  description = "Password or token the model pods pull the engine image with"
  type        = string
  default     = ""
  sensitive   = true
}

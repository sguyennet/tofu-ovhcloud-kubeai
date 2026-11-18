variable "chart_version" {
  description = "external-dns chart version"
  type        = string
  default     = "1.21.1"
}

variable "namespace" {
  description = "Namespace where ExternalDNS is deployed"
  type        = string
  default     = "external-dns"
}

variable "dns_domain" {
  description = "OVHcloud DNS zone managed by ExternalDNS"
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]+\\.(.+)", var.dns_domain))
    error_message = "The DNS domain is not valid"
  }
}

variable "txt_owner_id" {
  description = "Identifier of this ExternalDNS instance, written in the TXT registry records"
  type        = string
}

variable "policy" {
  description = "How records are synchronized: sync, upsert-only or create-only"
  type        = string
  default     = "sync"

  validation {
    condition     = can(regex("^(sync|upsert-only|create-only)$", var.policy))
    error_message = "The policy must be either sync, upsert-only or create-only"
  }
}

variable "sources" {
  description = "Kubernetes resources watched by ExternalDNS"
  type        = list(string)
  default     = ["ingress", "service"]
}

variable "ovh_endpoint" {
  description = "OVHcloud API endpoint"
  type        = string
  default     = "ovh-eu"

  validation {
    condition     = can(regex("^(ovh-eu|ovh-ca|ovh-us)$", var.ovh_endpoint))
    error_message = "The OVHcloud API endpoint must be either ovh-eu, ovh-ca or ovh-us"
  }
}

variable "api_dns_application_key" {
  description = "OVHcloud API application key allowed to manage the DNS zone"
  type        = string

  validation {
    condition     = can(regex("^(([0-9]|[a-zA-Z]){16})$", var.api_dns_application_key))
    error_message = "The application key does not have the right format"
  }
}

variable "api_dns_application_secret" {
  description = "OVHcloud API application secret allowed to manage the DNS zone"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^(([0-9]|[a-zA-Z]){32})$", var.api_dns_application_secret))
    error_message = "The application secret does not have the right format"
  }
}

variable "api_dns_consumer_key" {
  description = "OVHcloud API consumer key allowed to manage the DNS zone"
  type        = string
  sensitive   = true

  validation {
    condition     = can(regex("^(([0-9]|[a-zA-Z]){32})$", var.api_dns_consumer_key))
    error_message = "The consumer key does not have the right format"
  }
}

variable "node_selector" {
  description = "Node labels the ExternalDNS pods are pinned to"
  type        = map(string)
  default     = {}
}

variable "chart_version" {
  description = "cert-manager chart version"
  type        = string
  default     = "v1.21.1"
}

variable "webhook_chart_version" {
  description = "cert-manager-webhook-ovh chart version"
  type        = string
  default     = "0.9.16"
}

variable "namespace" {
  description = "Namespace where cert-manager and the OVHcloud webhook are deployed"
  type        = string
  default     = "cert-manager"
}

variable "dns_domain" {
  description = "OVHcloud DNS zone solving the ACME DNS-01 challenges, also used as the webhook group name"
  type        = string

  validation {
    condition     = can(regex("^[0-9A-Za-z_-]+\\.(.+)", var.dns_domain))
    error_message = "The DNS domain is not valid"
  }
}

variable "email" {
  description = "Email address registered on the ACME account"
  type        = string

  validation {
    condition     = can(regex("^[^@]+@[^@]+\\.[^@]+$", var.email))
    error_message = "The email address is not valid"
  }
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
  description = "Node labels the cert-manager and webhook pods are pinned to"
  type        = map(string)
  default     = {}
}

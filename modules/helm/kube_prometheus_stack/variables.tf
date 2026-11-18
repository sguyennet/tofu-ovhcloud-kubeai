variable "chart_version" {
  description = "kube-prometheus-stack chart version"
  type        = string
  default     = "89.2.4"
}

variable "namespace" {
  description = "Namespace where the monitoring stack is deployed"
  type        = string
  default     = "monitoring"
}

variable "fqdn" {
  description = "Hostname Grafana is served on. ExternalDNS creates the record from the ingress and cert-manager signs the certificate for it."
  type        = string
}

variable "ingress_class" {
  description = "IngressClass of the Grafana ingress"
  type        = string
}

variable "certificate_issuer" {
  description = "cert-manager ClusterIssuer signing the Grafana certificate"
  type        = string
}

variable "admin_user" {
  description = "Login of the Grafana administrator. Grafana treats this as a username rather than an address, so an address works but is not verified or mailed to."
  type        = string
}

variable "admin_password" {
  description = "Password of the Grafana admin account"
  type        = string
  sensitive   = true
}

variable "allow_list" {
  description = "IP addresses and CIDR ranges allowed to reach Grafana. Empty means any address, which for a dashboard carrying cluster internals is worth thinking about."
  type        = list(string)
  default     = []
}

variable "retention" {
  description = "How long Prometheus keeps samples. The stack is sized for reading the last few days of a lab rather than for long term capacity planning."
  type        = string
  default     = "15d"
}

variable "storage_size" {
  description = "Size of the volume holding the Prometheus time series database"
  type        = string
  default     = "50Gi"
}

variable "storage_class" {
  description = "StorageClass of the Prometheus volume. Empty uses the cluster default, which on MKS is block storage and is what a single Prometheus wants."
  type        = string
  default     = ""
}

variable "node_selector" {
  description = "Node labels the monitoring components are pinned to. The GPU nodes are left for the models, so this points at the platform pool."
  type        = map(string)
  default     = {}
}

variable "dashboards_path" {
  description = "Directory holding the Grafana dashboard documents to load. Each file becomes a ConfigMap that the Grafana sidecar picks up."
  type        = string
  default     = ""
}

variable "model_namespace" {
  description = "Namespace the model pods run in, scraped for vLLM metrics"
  type        = string
  default     = "kubeai"
}

variable "gpu_operator_namespace" {
  description = "Namespace the GPU operator runs in, scraped for DCGM metrics"
  type        = string
  default     = "gpu-operator"
}

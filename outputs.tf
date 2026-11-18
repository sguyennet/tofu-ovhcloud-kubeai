output "private_network_id" {
  description = "Private network OpenStack ID in the region"
  value       = module.private_network.network.regions_openstack_ids[var.region]
}

output "private_subnet_cidr" {
  description = "Private subnet CIDR"
  value       = module.private_network.subnets[0].cidr
}

output "gateway_ips" {
  description = "Public IPs of the gateway"
  value       = module.private_network.gateways[0].external_information
}

output "cluster_id" {
  description = "Managed Kubernetes cluster ID"
  value       = module.kubernetes.cluster_id
}

output "cluster_name" {
  description = "Managed Kubernetes cluster name"
  value       = module.kubernetes.cluster_name
}

output "kubeconfig_file" {
  description = "kubeconfig of the cluster"
  value       = module.kubernetes.kubeconfig_file
  sensitive   = true
}

output "ingress_class" {
  description = "Default IngressClass of the cluster"
  value       = module.ingress_haproxy.ingress_class
}

output "ingress_ip" {
  description = "IP address of the HAProxy ingress controller load balancer"
  value       = local.ingress_ip
}

output "cluster_issuers" {
  description = "ClusterIssuers available to sign certificates"
  value       = module.cert_manager.cluster_issuers
}

output "dns_domain" {
  description = "DNS zone managed by ExternalDNS"
  value       = var.ovh_dns_domain
}

output "open_webui_url" {
  description = "URL of Open WebUI"
  value       = module.kubeai.open_webui_url
}

output "valkey_host" {
  description = "Host of the managed Valkey endpoint"
  value       = module.valkey.host
}

output "valkey_port" {
  description = "Port of the managed Valkey endpoint"
  value       = module.valkey.port
}

output "valkey_username" {
  description = "User Open WebUI authenticates as on the managed Valkey cluster"
  value       = module.valkey.username
}

output "valkey_password" {
  description = "Password of the Valkey user"
  value       = module.valkey.password
  sensitive   = true
}

output "postgresql_host" {
  description = "Host of the managed PostgreSQL endpoint"
  value       = module.postgresql.host
}

output "postgresql_port" {
  description = "Port of the managed PostgreSQL endpoint"
  value       = module.postgresql.port
}

output "postgresql_username" {
  description = "PostgreSQL administrator"
  value       = module.postgresql.username
}

output "postgresql_password" {
  description = "Password of the PostgreSQL administrator"
  value       = module.postgresql.password
  sensitive   = true
}

output "postgresql_database" {
  description = "Database Open WebUI uses on the PostgreSQL cluster"
  value       = module.postgresql.database_name
}

output "bucket_name" {
  description = "Object Storage bucket holding the Open WebUI uploads"
  value       = module.object_storage.bucket_name
}

output "bucket_endpoint_url" {
  description = "S3 endpoint serving the bucket"
  value       = module.object_storage.endpoint_url
}

output "grafana_url" {
  description = "URL of Grafana, empty when the monitoring stack is not deployed"
  value       = var.monitoring_enabled ? one(module.monitoring[*].grafana_url) : ""
}

output "kubeai_namespace" {
  description = "Namespace where KubeAI and Open WebUI are deployed"
  value       = module.kubeai.namespace
}

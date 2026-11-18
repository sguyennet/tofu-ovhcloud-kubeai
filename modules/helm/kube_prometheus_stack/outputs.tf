output "namespace" {
  description = "Namespace where the monitoring stack is deployed"
  value       = var.namespace
}

output "grafana_url" {
  description = "URL of Grafana"
  value       = "https://${var.fqdn}"
}

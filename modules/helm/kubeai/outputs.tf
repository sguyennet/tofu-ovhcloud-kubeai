output "namespace" {
  description = "Namespace where KubeAI and Open WebUI are deployed"
  value       = helm_release.kubeai.namespace
}

output "open_webui_url" {
  description = "URL of Open WebUI"
  value       = "https://${var.fqdn}"
}

output "models" {
  description = "Models deployed with the cluster"
  value       = [for manifest in kubectl_manifest.models : manifest.name]
}




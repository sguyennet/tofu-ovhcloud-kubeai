output "namespace" {
  description = "Namespace where the image mirror is deployed"
  value       = var.namespace
}

output "mirrored_registries" {
  description = "Registries a pull can resolve from a peer"
  value       = var.mirrored_registries
}

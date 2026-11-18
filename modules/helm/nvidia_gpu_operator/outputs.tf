output "namespace" {
  description = "Namespace where the GPU operator is deployed"
  value       = helm_release.gpu-operator.namespace
}

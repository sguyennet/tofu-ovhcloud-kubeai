output "namespace" {
  description = "Namespace where the HAProxy ingress controller is deployed"
  value       = helm_release.haproxy-ingress.namespace
}

output "service_name" {
  description = "Name of the HAProxy ingress controller LoadBalancer service"
  value       = "${helm_release.haproxy-ingress.name}-kubernetes-ingress"
}

output "ingress_class" {
  description = "Name of the IngressClass handled by this controller"
  value       = var.ingress_class
}

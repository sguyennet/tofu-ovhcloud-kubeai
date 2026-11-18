output "namespace" {
  description = "Namespace where cert-manager is deployed"
  value       = helm_release.cert-manager.namespace
}

output "cluster_issuers" {
  description = "Names of the ClusterIssuers created by the OVHcloud webhook"
  value       = local.issuers[*].name
}

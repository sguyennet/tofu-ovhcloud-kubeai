output "cluster_id" {
  description = "Managed Kubernetes cluster ID"
  value       = ovh_cloud_project_kube.cluster.id
}

output "cluster_name" {
  description = "Managed Kubernetes cluster name"
  value       = ovh_cloud_project_kube.cluster.name
}

output "kubeconfig_file" {
  description = "kubeconfig file"
  value       = ovh_cloud_project_kube.cluster.kubeconfig
  sensitive   = true
}

output "kubeconfig_attributes" {
  description = "kubeconfig attributes (host and certificates)"
  value       = ovh_cloud_project_kube.cluster.kubeconfig_attributes
  sensitive   = true
}

output "node_pools" {
  description = "Node pools"
  value       = ovh_cloud_project_kube_nodepool.node_pools[*]
}

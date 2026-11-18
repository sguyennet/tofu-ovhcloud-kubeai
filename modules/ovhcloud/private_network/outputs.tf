output "network" {
  description = "Network"
  value       = ovh_cloud_project_network_private.private_net
}

output "subnets" {
  description = "Subnets"
  value       = ovh_cloud_project_network_private_subnet_v2.private_subnet[*]
}

output "gateways" {
  description = "Gateways"
  value       = ovh_cloud_project_gateway.gateway[*]
}
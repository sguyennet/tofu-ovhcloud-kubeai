output "cluster_id" {
  description = "Managed Valkey cluster ID"
  value       = ovh_cloud_project_database.valkey.id
}

output "host" {
  description = "Host of the Valkey endpoint"
  value       = ovh_cloud_project_database.valkey.endpoints[0].domain
}

output "port" {
  description = "Port of the Valkey endpoint"
  value       = ovh_cloud_project_database.valkey.endpoints[0].port
}

output "username" {
  description = "Valkey user"
  value       = ovh_cloud_project_database_valkey_user.default.name
}

output "password" {
  description = "Password of the Valkey user"
  value       = ovh_cloud_project_database_valkey_user.default.password
  sensitive   = true
}

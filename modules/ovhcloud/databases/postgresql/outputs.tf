output "cluster_id" {
  description = "Managed PostgreSQL cluster ID"
  value       = ovh_cloud_project_database.postgresql.id
}

output "host" {
  description = "Host of the PostgreSQL endpoint"
  value       = ovh_cloud_project_database.postgresql.endpoints[0].domain
}

output "port" {
  description = "Port of the PostgreSQL endpoint"
  value       = ovh_cloud_project_database.postgresql.endpoints[0].port
}

output "username" {
  description = "PostgreSQL administrator"
  value       = ovh_cloud_project_database_postgresql_user.avnadmin.name
}

output "password" {
  description = "Password of the PostgreSQL administrator"
  value       = ovh_cloud_project_database_postgresql_user.avnadmin.password
  sensitive   = true
}

output "database_name" {
  description = "Database created in the cluster"
  value       = ovh_cloud_project_database_database.database.name
}

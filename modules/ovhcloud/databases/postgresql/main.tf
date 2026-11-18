resource "ovh_cloud_project_database" "postgresql" {
  service_name = var.service_name
  engine       = "postgresql"
  version      = var.postgresql_version
  description  = var.description
  plan         = var.plan
  flavor       = var.flavor

  # One node on discovery, a pair on production, three on advanced. Every node is
  # attached to the subnet the cluster nodes sit on, so Open WebUI reaches the
  # endpoint over the private network.
  dynamic "nodes" {
    for_each = contains(["essential", "discovery"], var.plan) ? [0] : (
      contains(["business", "production"], var.plan) ? [0, 1] : [0, 1, 2]
    )
    content {
      region     = var.region
      network_id = var.network_id
      subnet_id  = var.subnet_id
    }
  }

  # A cluster is unreachable until an address is authorised, a private network
  # does not exempt it from the rule.
  ip_restrictions {
    description = "Private subnet of the cluster"
    ip          = var.allowed_ip
  }
}

# The administrator comes with the cluster, but its password is only ever returned
# by a reset, which is what password_reset asks for here. The value is a marker,
# not a password: the reset happens again whenever it changes.
resource "ovh_cloud_project_database_postgresql_user" "avnadmin" {
  service_name   = var.service_name
  cluster_id     = ovh_cloud_project_database.postgresql.id
  name           = "avnadmin"
  password_reset = "reset"
}

resource "ovh_cloud_project_database_database" "database" {
  service_name = var.service_name
  cluster_id   = ovh_cloud_project_database.postgresql.id
  engine       = "postgresql"
  name         = var.database_name
}

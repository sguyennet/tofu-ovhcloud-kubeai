resource "ovh_cloud_project_database" "valkey" {
  service_name = var.service_name
  engine       = "valkey"
  version      = var.valkey_version
  description  = var.description
  plan         = var.plan
  flavor       = var.flavor

  # The essential plan runs a single node, business and production a pair. Every
  # node is attached to the subnet the cluster nodes sit on, so the pods reach the
  # endpoint over the private network instead of going out through the gateway.
  dynamic "nodes" {
    for_each = contains(["essential", "discovery"], var.plan) ? [0] : [0, 1]
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

# The default user comes with the cluster, but its password is only ever returned
# by a reset, which is what password_reset asks for here. The value is a marker,
# not a password: the reset happens again whenever it changes.
resource "ovh_cloud_project_database_valkey_user" "default" {
  service_name   = var.service_name
  cluster_id     = ovh_cloud_project_database.valkey.id
  name           = "default"
  password_reset = "reset"
  categories     = ["+@all"]
  keys           = ["*"]
}

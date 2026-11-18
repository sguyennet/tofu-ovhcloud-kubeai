resource "ovh_cloud_project_kube" "cluster" {
  service_name       = var.service_name
  name               = var.cluster.name
  region             = var.region
  version            = var.cluster.version
  plan               = var.cluster.plan
  kube_proxy_mode    = "ipvs"
  private_network_id = var.cluster.network_id
  nodes_subnet_id    = var.cluster.subnet_id

  # Which interface of a node carries its egress traffic. Routing through the
  # private network sends everything out of one gateway, a single exit point whose
  # bandwidth is shared by every node and bounded by its size; routing through the
  # public interface of each node gives every one of them its own, which is what a
  # node pulling a container image of several gigabytes wants.
  private_network_configuration {
    default_vrack_gateway              = ""
    private_network_routing_as_default = var.private_network_routing_as_default
  }
}

resource "ovh_cloud_project_kube_nodepool" "node_pools" {
  count = length(var.node_pools)

  service_name = var.service_name
  kube_id      = ovh_cloud_project_kube.cluster.id
  name         = var.node_pools[count.index].name
  flavor_name  = var.node_pools[count.index].flavor
  max_nodes    = var.node_pools[count.index].max_nodes
  min_nodes    = var.node_pools[count.index].min_nodes
  autoscale    = var.node_pools[count.index].autoscale

  # On an autoscaled pool the number of nodes belongs to the autoscaler, leaving
  # desired_nodes unset keeps it computed instead of fighting it on every plan.
  desired_nodes      = var.node_pools[count.index].autoscale ? null : var.node_pools[count.index].desired_nodes
  availability_zones = var.node_pools[count.index].availability_zones != null ? var.node_pools[count.index].availability_zones : null

  # Labels and taints propagated by the node pool to each of its nodes.
  dynamic "template" {
    for_each = length(var.node_pools[count.index].labels) > 0 || length(var.node_pools[count.index].taints) > 0 ? [1] : []

    content {
      metadata {
        labels      = var.node_pools[count.index].labels
        annotations = {}
        finalizers  = []
      }

      spec {
        taints        = var.node_pools[count.index].taints
        unschedulable = false
      }
    }
  }
}
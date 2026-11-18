resource "ovh_cloud_project_network_private" "private_net" {
  service_name = var.service_name
  name         = var.network.name
  vlan_id      = var.network.vlan_id
  regions      = var.regions
}

resource "ovh_cloud_project_network_private_subnet_v2" "private_subnet" {
  count = length(var.subnets)

  service_name      = var.service_name
  name              = var.subnets[count.index].name
  network_id        = ovh_cloud_project_network_private.private_net.regions_openstack_ids[var.subnets[count.index].region]
  region            = var.subnets[count.index].region
  gateway_ip        = var.subnets[count.index].gateway_ip
  cidr              = var.subnets[count.index].cidr
  dns_nameservers   = ["213.186.33.99"]
  dhcp              = true
  enable_gateway_ip = true

  allocation_pools {
    start = var.subnets[count.index].dhcp_start
    end   = var.subnets[count.index].dhcp_end
  }
}

resource "ovh_cloud_project_gateway" "gateway" {
  count = length(var.gateways)

  service_name = var.service_name
  name         = var.gateways[count.index].name
  model        = var.gateways[count.index].size
  region       = var.gateways[count.index].region
  network_id   = ovh_cloud_project_network_private.private_net.regions_openstack_ids[var.gateways[count.index].region]
  subnet_id    = ovh_cloud_project_network_private_subnet_v2.private_subnet[index(ovh_cloud_project_network_private_subnet_v2.private_subnet.*.region, var.gateways[count.index].region)].id
}
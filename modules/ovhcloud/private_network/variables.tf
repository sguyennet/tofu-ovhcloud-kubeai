variable "service_name" {
  description = "Public Cloud project ID"
  type        = string

  validation {
    condition     = length(var.service_name) == 32 && can(regex("^[A-Za-z0-9]*$", var.service_name))
    error_message = "The service name is not a project ID"
  }
}

variable "regions" {
  description = "Regions"
  type        = list(string)

  validation {
    condition     = can([for region in var.regions : regex("^((BHS|DE|GRA|MUM|SBG|SPG|SYD|UK|WAW)[0-9]{1,2}|RBX-[A-Z]|EU-WEST-PAR|EU-SOUTH-MIL|CA-EAST-TOR)$", region)])
    error_message = "The region is not valid"
  }
}

variable "network" {
  description = "Private Network Parameters"
  type = object({
    name    = string
    vlan_id = string
  })

  validation {
    condition     = length(var.network.vlan_id) < 5 && can(regex("^[0-9]*$", var.network.vlan_id))
    error_message = "The VLAN ID is not a number between 0 and 4096"
  }
}

variable "subnets" {
  description = "Subnets parameters"
  type = list(object({
    name       = string
    region     = string
    cidr       = string
    gateway_ip = string
    dhcp_start = string
    dhcp_end   = string
  }))

  validation {
    condition     = can([for subnet in var.subnets : regex("^((BHS|DE|GRA|MUM|SBG|SPG|SYD|UK|WAW)[0-9]{1,2}|RBX-[A-Z]|EU-WEST-PAR|EU-SOUTH-MIL|CA-EAST-TOR)$", subnet.region)])
    error_message = "The region is not valid"
  }

  validation {
    condition     = can([for subnet in var.subnets : cidrnetmask(subnet.cidr)])
    error_message = "All elements must have a valid IPv4 CIDR"
  }

  validation {
    condition     = can([for subnet in var.subnets : regex("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", subnet.gateway_ip)])
    error_message = "All elements must have a valid gateway IP address"
  }

  validation {
    condition     = can([for subnet in var.subnets : regex("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", subnet.dhcp_start)])
    error_message = "All elements must have a valid DHCP start IP address"
  }

  validation {
    condition     = can([for subnet in var.subnets : regex("^(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\\.(25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)$", subnet.dhcp_end)])
    error_message = "All elements must have a valid DHCP end IP address"
  }
}

variable "gateways" {
  description = "Gateways Parameters"
  type = list(object({
    name   = string
    size   = string
    region = string
  }))

  validation {
    condition     = can([for gateway in var.gateways : regex("^(s|m|l|xl|2xl)$", gateway.size)])
    error_message = "The gateway size must be either s, m, l, xl, or 2xl"
  }

  validation {
    condition     = can([for gateway in var.gateways : regex("^((BHS|DE|GRA|MUM|SBG|SPG|SYD|UK|WAW)[0-9]{1,2}|RBX-[A-Z]|EU-WEST-PAR|EU-SOUTH-MIL|CA-EAST-TOR)$", gateway.region)])
    error_message = "The region is not valid"
  }
}

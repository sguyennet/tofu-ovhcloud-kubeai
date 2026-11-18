variable "service_name" {
  description = "Public Cloud project ID"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32}$", var.service_name))
    error_message = "The service name is not a project ID"
  }
}

variable "region" {
  description = "Region"
  type        = string

  validation {
    condition     = can(regex("^((BHS|DE|GRA|MUM|SBG|SPG|SYD|UK|WAW)[0-9]{1,2}|RBX-[A-Z]|EU-WEST-PAR|EU-SOUTH-MIL|CA-EAST-TOR)$", var.region))
    error_message = "The region is not valid"
  }
}

variable "private_network_routing_as_default" {
  description = "Route the egress traffic of the nodes through their private interface, and so through the gateway of the private network, rather than through the public interface each node already carries. False leaves the gateway out of the path."
  type        = bool
  default     = true
}

variable "cluster" {
  description = "Managed Kubernetes Cluster parameters"
  type = object({
    name       = string
    version    = string
    plan       = string
    network_id = string
    subnet_id  = string
  })

  validation {
    condition     = can(regex("^(1\\.[0-9]{1,2})$", var.cluster.version))
    error_message = "The Kubernetes version is not valid"
  }

  validation {
    condition     = can(regex("^(free|standard)$", var.cluster.plan))
    error_message = "The Kubernetes cluster plan must be either free or standard"
  }
}

variable "node_pools" {
  description = "Node Pool parameters. Labels and taints are applied to every node of the pool."
  type = list(object({
    name               = string
    flavor             = string
    desired_nodes      = optional(string)
    max_nodes          = string
    min_nodes          = string
    availability_zones = list(string)
    autoscale          = optional(bool, false)
    labels             = optional(map(string), {})
    taints             = optional(list(map(string)), [])
  }))

  default = [{
    name               = "node-pool"
    flavor             = "b3-8"
    desired_nodes      = "3"
    max_nodes          = "5"
    min_nodes          = "0"
    availability_zones = []
  }]
}

variable "service_name" {
  description = "OVHcloud Public Cloud project ID"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32}$", var.service_name))
    error_message = "The service name is not a project ID"
  }
}

variable "region" {
  description = "Region hosting the cluster nodes. Managed databases are placed in a macro region (GRA) rather than in one of its availability zones (GRA11)."
  type        = string

  validation {
    condition     = can(regex("^(BHS|DE|GRA|RBX|SBG|SGP|UK|WAW|EU-WEST-PAR|EU-SOUTH-MIL|AP-SOUTH-MUM)$", var.region))
    error_message = "The region does not host the Public Cloud Databases offer"
  }
}

variable "description" {
  description = "Name of the cluster as displayed in the OVHcloud control panel"
  type        = string
}

variable "postgresql_version" {
  description = "PostgreSQL major version. 13 and above carry the pgvector extension, which Open WebUI needs for its vector store."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{2}$", var.postgresql_version))
    error_message = "The PostgreSQL version is a major version, for example 17"
  }

  validation {
    condition     = tonumber(var.postgresql_version) >= 13
    error_message = "pgvector is only available from PostgreSQL 13 on"
  }
}

variable "plan" {
  description = "Service plan of the cluster: discovery runs a single node, production a pair, advanced three"
  type        = string

  validation {
    condition     = contains(["essential", "discovery", "business", "production", "enterprise", "advanced"], var.plan)
    error_message = "The plan must be essential, discovery, business, production, enterprise or advanced"
  }
}

variable "flavor" {
  description = "Node flavor of the cluster, for example db1-4 or b3-8"
  type        = string

  validation {
    condition     = can(regex("^(b|db)[0-9]-[0-9]{1,3}$", var.flavor))
    error_message = "The flavor is not valid"
  }
}

variable "network_id" {
  description = "OpenStack ID, in the region, of the private network the nodes are attached to"
  type        = string
}

variable "subnet_id" {
  description = "ID of the private subnet the nodes are attached to"
  type        = string
}

variable "allowed_ip" {
  description = "CIDR authorised to open connections to the cluster"
  type        = string

  validation {
    condition     = can(cidrnetmask(var.allowed_ip))
    error_message = "The allowed IP must be a CIDR"
  }
}

variable "database_name" {
  description = "Name of the database created in the cluster"
  type        = string
}

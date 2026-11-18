variable "service_name" {
  description = "OVHcloud Public Cloud project ID"
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9]{32}$", var.service_name))
    error_message = "The service name is not a project ID"
  }
}

variable "region" {
  description = "Region hosting the shares, the OpenStack one rather than the macro region: the shares live in the same availability zone as the cluster."
  type        = string

  validation {
    condition     = can(regex("^((BHS|DE|GRA|MUM|SBG|SPG|SYD|UK|WAW)[0-9]{1,2}|RBX-[A-Z])$", var.region))
    error_message = "The region does not offer the shared filesystem service. It is absent from the three availability zone regions, EU-WEST-PAR and EU-SOUTH-MIL among them."
  }
}

variable "namespace" {
  description = "Namespace where the drivers are deployed"
  type        = string
  default     = "kube-system"
}

variable "share_network_name" {
  description = "Name of the share network binding the shares to the private network"
  type        = string
}

variable "network_id" {
  description = "OpenStack ID, in the region, of the private network the shares are reachable on"
  type        = string
}

variable "subnet_id" {
  description = "ID of the private subnet the shares are reachable on"
  type        = string
}

variable "subnet_cidr" {
  description = "CIDR of the private subnet. It is both the address range allowed to mount a share and the one the driver picks the export location from."
  type        = string

  validation {
    condition     = can(cidrnetmask(var.subnet_cidr))
    error_message = "The subnet CIDR is not a CIDR"
  }
}

variable "storage_class_name" {
  description = "Name of the StorageClass provisioning the shares"
  type        = string
  default     = "csi-manila-nfs"
}

variable "share_type" {
  description = "Share type requested from the shared filesystem service"
  type        = string
  default     = "standard-1az"
}

variable "user_description" {
  description = "Description of the Public Cloud user the driver authenticates as, as displayed in the OVHcloud control panel"
  type        = string
}

variable "role_name" {
  description = "Role of the Public Cloud user the driver authenticates as. share_operator grants the shared filesystem service and nothing else."
  type        = string
  default     = "share_operator"
}

variable "tolerations" {
  description = "Tolerations of the node plugin, which has to run on every node mounting a share. The default one matches the taint reserving the GPU nodes for the KubeAI models, whose pods are the ones reading the model cache."
  type = list(object({
    key      = string
    operator = string
    value    = optional(string)
    effect   = string
  }))

  default = [{
    key      = "nvidia.com/gpu"
    operator = "Equal"
    value    = "present"
    effect   = "NoSchedule"
  }]
}

variable "node_selector" {
  description = "Node selector of the controller, which only talks to the OpenStack API and belongs with the other platform components"
  type        = map(string)
  default     = {}
}

variable "csi_driver_nfs_chart_version" {
  description = "csi-driver-nfs chart version"
  type        = string
  default     = "4.13.4"
}

variable "manila_csi_chart_version" {
  description = "openstack-manila-csi chart version"
  type        = string
  default     = "2.36.2"
}

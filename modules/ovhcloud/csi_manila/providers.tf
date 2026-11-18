terraform {
  required_providers {
    ovh = {
      source = "ovh/ovh"
    }

    openstack = {
      source = "opentofu/openstack"
    }

    helm = {
      source = "opentofu/helm"
    }

    kubectl = {
      source = "alekc/kubectl"
    }
  }
}

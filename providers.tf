terraform {
  required_version = ">= 1.6"

  required_providers {
    ovh = {
      source  = "ovh/ovh"
      version = "~> 2.19"
    }

    helm = {
      source  = "opentofu/helm"
      version = "~> 3.2"
    }

    kubectl = {
      source  = "alekc/kubectl"
      version = "2.1.6"
    }

    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    openstack = {
      source  = "opentofu/openstack"
      version = "~> 3.0"
    }
  }
}

# The OVHcloud provider is configured through the OVH_* environment variables
# (see README.md).
provider "ovh" {}

# The OpenStack provider is configured through the OS_* environment variables, or
# through a named cloud in clouds.yaml. It is only used to create the share
# network of the shared filesystem service, which the OVHcloud API does not
# expose.
provider "openstack" {}

provider "helm" {
  kubernetes = {
    host                   = module.kubernetes.kubeconfig_attributes[0].host
    client_certificate     = base64decode(module.kubernetes.kubeconfig_attributes[0].client_certificate)
    client_key             = base64decode(module.kubernetes.kubeconfig_attributes[0].client_key)
    cluster_ca_certificate = base64decode(module.kubernetes.kubeconfig_attributes[0].cluster_ca_certificate)
  }
}

provider "kubectl" {
  host                   = module.kubernetes.kubeconfig_attributes[0].host
  client_certificate     = base64decode(module.kubernetes.kubeconfig_attributes[0].client_certificate)
  client_key             = base64decode(module.kubernetes.kubeconfig_attributes[0].client_key)
  cluster_ca_certificate = base64decode(module.kubernetes.kubeconfig_attributes[0].cluster_ca_certificate)
  load_config_file       = false
}

terraform {
  required_providers {
    helm = {
      source = "opentofu/helm"
    }

    kubectl = {
      source  = "alekc/kubectl"
      version = "2.1.6"
    }
  }
}

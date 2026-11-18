terraform {
  required_providers {
    helm = {
      source = "opentofu/helm"
    }

    kubectl = {
      source = "alekc/kubectl"
    }
  }
}

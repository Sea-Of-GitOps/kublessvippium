terraform {
  required_providers {
    kind = {
      source = "tehcyx/kind"
      version = "0.11.0"
    }
    local = {
      source = "hashicorp/local"
      version = "2.9.0"
    }
    helm = {
      source = "opentofu/helm"
      version = "3.2.0"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
      version = "1.19.0"
    }
  }
}

terraform {
  required_providers {
    kind = {
      source = "tehcyx/kind"
      version = "0.8.0"
    }
    local = {
      source = "hashicorp/local"
      version = "~> 2.5"
    }
    helm = {
      source = "opentofu/helm"
      version = "3.0.0-pre2"
    }
    kubectl = {
      source = "gavinbunney/kubectl"
      version = "1.19.0"
    }
  }
}

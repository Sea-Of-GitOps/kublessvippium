variable "cluster_name" {
  type        = string
  description = "Define a cluster name which will be appended to kind"
  default     = "kublessvippium-cluster"
}

variable "node_image" {
  type        = string
  description = "The Docker image to use for the kind nodes"
  default     = "kindest/node:v1.27.1"
}

variable "k8s_service_host" {
  type        = string
  description = "The Kubernetes service host"
  default     = "172.18.99.254"
}

variable "k8s_service_port" {
  description = "The Kubernetes service port"
  default     = "6443"
}

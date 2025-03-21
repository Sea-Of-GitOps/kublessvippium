output "cluster_name" {
  value = kind_cluster.default.name
}


output "endpoint" {
  value = kind_cluster.default.endpoint
}

resource "local_file" "kubeconfig" {
    content  = kind_cluster.default.kubeconfig
    filename = "kubeconfig"
}
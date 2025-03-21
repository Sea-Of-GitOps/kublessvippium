provider kind {
  # Configuration options
}

provider local {
  # Configuration options
}

provider "helm" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
}

provider "kubectl" {
  config_path = local_file.kubeconfig.filename
}



resource "kind_cluster" "default" {
    name = var.clustername
    node_image = "kindest/node:v1.27.1"
    kind_config  {
        kind = "Cluster"
        api_version = "kind.x-k8s.io/v1alpha4"
        networking {
          disable_default_cni = true
          kube_proxy_mode = "none"
        }
        node {
            role = "control-plane"
            kubeadm_config_patches = [<<-EOT
            kind: ClusterConfiguration
            apiServer:
                certSANs:
                - localhost
                - 127.0.0.1
                - host.docker.internal
                - 172.18.99.254
            EOT
            ]
            extra_port_mappings {
                container_port = 80
                host_port      = 80
            }
            extra_port_mappings {
                container_port = 443
                host_port      = 443
            }
        }
        node {
            role =  "worker"
        }
        node {
            role =  "worker"
        }
    }    



}


resource "kubectl_manifest" "kubevip" {
  depends_on = [kind_cluster.default, local_file.kubeconfig]
  yaml_body = file("./kubernetes_manifest/kubevip-job.yaml")
}





resource "kubectl_manifest" "prometheus-namespace" {
  depends_on = [kind_cluster.default, local_file.kubeconfig]
  yaml_body = file("./kubernetes_manifest/prometheus-namespace.yaml")
}

data "kubectl_file_documents" "prometheus-crds-content" {
    content = file("./kubernetes_manifest/prometheus-crds.yaml")
}

resource "kubectl_manifest" "prometheus-crds" {
    depends_on = [kind_cluster.default, local_file.kubeconfig, kubectl_manifest.prometheus-namespace, data.kubectl_file_documents.prometheus-crds-content]
    server_side_apply = true
    for_each  = data.kubectl_file_documents.prometheus-crds-content.manifests
    yaml_body = each.value
}



resource "helm_release" "cilium" {
  wait = false
  name = "cilium"
  repository = "https://helm.cilium.io/"
  namespace = "kube-system"
  create_namespace = true
  chart      = "cilium"
  depends_on = [kind_cluster.default, local_file.kubeconfig, kubectl_manifest.prometheus-crds ]
  set = [
    {
      name  = "operator.replicas"
      value = "1"
    },
    {
      name  = "kubeProxyReplacement"
      value = "true"
    },
    {
      name  = "k8sServiceHost"
      value = "172.18.99.254"
    },
    {
      name  = "k8sServicePort"
      value = "6443"
    },
    {
      name  = "l2announcements.enable"
      value = "true"
    },
    {
      name  = "socketLB.enable"
      value = "true"
    },
    {
      name  = "ingressController.enabled"
      value = "true"
    },
    {
      name  = "operator.prometheus.enabled"
      value = "true"
    },
    {
      name  = "operator.prometheus.serviceMonitor.enabled"
      value = "true"
    },
    {
      name  = "prometheus.serviceMonitor.enabled"
      value = "true"
    },
    {
      name  = "hubble.relay.enabled"
      value = "true"
    },
    {
      name  = "hubble.ui.enabled"
      value = "true"
    },
    {
      name  = "hubble.metrics.dashboards.enabled"
      value = "true"
    },
    {
      name  = "hubble.metrics.dashboards.namespace"
      value = "monitoring"
    },
    {
      name  = "hubble.metrics.dashboards.annotations.grafana_folder"
      value = "Hubble"
    }
,
    {
      name  = "hubble.metrics.enableOpenMetrics"
      value = "true"
    },
    {
      name  = "hubble.metrics.enabled"
      value = "{dns,drop,tcp,flow:sourceContext=workload-name|reserved-identity;destinationContext=workload-name|reserved-identity,port-distribution,icmp,kafka:labelsContext=source_namespace\\,source_workload\\,destination_namespace\\,destination_workload\\,traffic_direction;sourceContext=workload-name|reserved-identity;destinationContext=workload-name|reserved-identity,policy:sourceContext=app|workload-name|pod|reserved-identity;destinationContext=app|workload-name|pod|dns|reserved-identity;labelsContext=source_namespace\\,destination_namespace,httpV2:exemplars=true;labelsContext=source_ip\\,source_namespace\\,source_workload\\,destination_ip\\,destination_namespace\\,destination_workload\\,traffic_direction}"
    },
    {
      name  = "hubble.enabled"
      value = "true"
    },
    {
      name  = "hubble.metrics.serviceMonitor.enabled"
      value = "true"
    },
    {
      name  = "ingressController.loadbalancerMode"
      value = "shared"
    }
  ]

}


resource "kubectl_manifest" "l2announcements" {
  depends_on = [kind_cluster.default, local_file.kubeconfig, helm_release.cilium, helm_release.metrics]
  server_side_apply = true
  yaml_body = file("./kubernetes_manifest/cilium-l2announcementpolicy.yaml")
}

resource "kubectl_manifest" "ippools" {
  depends_on = [kind_cluster.default, local_file.kubeconfig, helm_release.cilium, helm_release.metrics]
  server_side_apply = true
  yaml_body = file("./kubernetes_manifest/cilium-loadbalancerippool.yaml")
}


resource "helm_release" "metrics" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  create_namespace = true
  dependency_update = true
  namespace = "metrics"
  version = "3.12.2"
  depends_on = [kind_cluster.default, local_file.kubeconfig, helm_release.cilium]
  values = [<<YAML
  defaultArgs:
  - --cert-dir=/tmp
  - --kubelet-preferred-address-types=InternalIP
  - --kubelet-insecure-tls
  - --kubelet-use-node-status-port
  - --metric-resolution=15s
  YAML
  ]
  cleanup_on_fail = true

}

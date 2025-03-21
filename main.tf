provider "kind" {}

provider "local" {}

provider "helm" {
  kubernetes = {
    config_path = local_file.kubeconfig.filename
  }
}

provider "kubectl" {
  config_path = local_file.kubeconfig.filename
}

resource "kind_cluster" "default" {
  name       = var.clustername
  node_image = "kindest/node:v1.27.1"
  kind_config {
    kind        = "Cluster"
    api_version = "kind.x-k8s.io/v1alpha4"
    networking {
      disable_default_cni = true
      kube_proxy_mode     = "none"
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
      role = "worker"
    }
    node {
      role = "worker"
    }
  }
}

resource "kubectl_manifest" "kubevip" {
  depends_on = [kind_cluster.default, local_file.kubeconfig]
  yaml_body  = <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: kube-vip-setup
  namespace: kube-system
spec:
  template:
    spec:
      restartPolicy: Never
      hostNetwork: true
      nodeSelector:
        node-role.kubernetes.io/control-plane: ""
      tolerations:
        - key: "node-role.kubernetes.io/control-plane"
          operator: "Exists"
          effect: "NoSchedule"
        - key: "node-role.kubernetes.io/master"
          operator: "Exists"
          effect: "NoSchedule"
        - key: node.kubernetes.io/not-ready
          operator: "Exists"
          effect: NoSchedule
        - key: node.kubernetes.io/not-ready
          operator: "Exists"
          effect: NoExecute
      containers:
      - name: kube-vip-installer
        image: busybox
        command: ["/bin/sh", "-c"]
        args:
          - |
            INTERFACE=$(ip route | awk '/default/ {print $5}')
            echo "Using interface: $INTERFACE"
            cat <<EOF > /etc/kubernetes/manifests/kube-vip.yaml
            apiVersion: v1
            kind: Pod
            metadata:
              name: kube-vip
              namespace: kube-system
            spec:
              containers:
              - args:
                - manager
                env:
                - name: vip_arp
                  value: "true"
                - name: port
                  value: "6443"
                - name: vip_interface
                  value: $INTERFACE
                - name: vip_cidr
                  value: "32"
                - name: cp_enable
                  value: "true"
                - name: cp_namespace
                  value: kube-system
                - name: vip_ddns
                  value: "false"
                - name: vip_leaderelection
                  value: "true"
                - name: vip_leaseduration
                  value: "5"
                - name: vip_renewdeadline
                  value: "3"
                - name: vip_retryperiod
                  value: "1"
                - name: address
                  value: 172.18.99.254
                - name: prometheus_server
                  value: :2112
                image: ghcr.io/kube-vip/kube-vip:v0.5.0
                imagePullPolicy: Always
                name: kube-vip
                securityContext:
                  capabilities:
                    add:
                    - NET_ADMIN
                    - NET_RAW
                volumeMounts:
                - mountPath: /etc/kubernetes/admin.conf
                  name: kubeconfig
              hostAliases:
              - hostnames:
                - kubernetes
                ip: 127.0.0.1
              hostNetwork: true
              volumes:
              - hostPath:
                  path: /etc/kubernetes/admin.conf
                name: kubeconfig
            EOF
        volumeMounts:
          - mountPath: /etc/kubernetes/manifests
            name: kube-manifests
      volumes:
        - name: kube-manifests
          hostPath:
            path: /etc/kubernetes/manifests
            type: Directory
YAML
}

resource "kubectl_manifest" "prometheus-namespace" {
  depends_on = [kind_cluster.default, local_file.kubeconfig]
  yaml_body  = file("./kubernetes_manifest/prometheus-namespace.yaml")
}

data "kubectl_file_documents" "prometheus-crds-content" {
  content = file("./kubernetes_manifest/prometheus-crds.yaml")
}

resource "kubectl_manifest" "prometheus-crds" {
  depends_on        = [kind_cluster.default, local_file.kubeconfig, kubectl_manifest.prometheus-namespace, data.kubectl_file_documents.prometheus-crds-content]
  server_side_apply = true
  for_each          = data.kubectl_file_documents.prometheus-crds-content.manifests
  yaml_body         = each.value
}



resource "helm_release" "cilium" {
  wait             = false
  name             = "cilium"
  repository       = "https://helm.cilium.io/"
  namespace        = "kube-system"
  create_namespace = true
  chart            = "cilium"
  depends_on       = [kind_cluster.default, local_file.kubeconfig, kubectl_manifest.prometheus-crds]
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
  depends_on        = [kind_cluster.default, local_file.kubeconfig, helm_release.cilium, helm_release.metrics]
  server_side_apply = true
  yaml_body         = <<YAML
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumL2AnnouncementPolicy
metadata:
  name: default
spec:
  nodeSelector:
    matchExpressions:
      - key: node-role.kubernetes.io/control-plane
        operator: DoesNotExist
  interfaces:
  - ^eth[0-9]+
  externalIPs: true
  loadBalancerIPs: true
---
YAML
}

resource "kubectl_manifest" "ippools" {
  depends_on        = [kind_cluster.default, local_file.kubeconfig, helm_release.cilium, helm_release.metrics]
  server_side_apply = true
  yaml_body         = <<YAML
---
apiVersion: "cilium.io/v2alpha1"
kind: CiliumLoadBalancerIPPool
metadata:
  name: "kind-docker-pool"
spec:
  blocks:
  - start: "172.18.99.99"
    stop: "172.18.99.110"
---
YAML
}


resource "helm_release" "metrics" {
  name              = "metrics-server"
  repository        = "https://kubernetes-sigs.github.io/metrics-server/"
  chart             = "metrics-server"
  create_namespace  = true
  dependency_update = true
  namespace         = "metrics"
  version           = "3.12.2"
  depends_on        = [kind_cluster.default, local_file.kubeconfig, helm_release.cilium]
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

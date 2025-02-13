resource "kubernetes_manifest" "gpu_nodepool" {
  count = var.enable_auto_mode_node_pool && var.enable_deep_seek_gpu ? 1 : 0

  depends_on = [
    module.eks,
    time_sleep.wait_for_kubernetes,
    data.aws_eks_cluster.cluster,
    data.aws_eks_cluster_auth.cluster,
    helm_release.karpenter,
    kubernetes_manifest.default_nodeclass
  ]

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu-nodepool"
    }
    spec = {
      limits = {
        "cpu" = "16"         # Total CPU for 2 nodes (8 * 2)
        "memory" = "64Gi"    # Total memory for 2 nodes (32 * 2)
        "nvidia.com/gpu" = "2"  # Total GPUs needed (1 * 2)
      }
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter   = "30s"
      }
      template = {
        metadata = {
          labels = {
            owner = "data-engineer"
            instanceType = "gpu"
          }
        }
        spec = {
          startupTaints = [
            {
              key    = "nvidia.com/gpu"
              value  = "Exists"
              effect = "NoSchedule"
            }
          ]
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "default"
          }
          requirements = [
            {
              key      = "eks.amazonaws.com/instance-family"
              operator = "In"
              values   = ["g4dn"]
            },
            {
              key      = "eks.amazonaws.com/instance-size"
              operator = "In"
              values   = ["2xlarge"]    # Specifically g4dn.2xlarge
            },
            {
              key      = "kubernetes.io/arch"
              operator = "In"
              values   = ["amd64"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["on-demand"]
            }
          ]
        }
      }
    }
  }
}

resource "kubernetes_manifest" "neuron_nodepool" {
  count = var.enable_auto_mode_node_pool && var.enable_deep_seek_neuron ? 1 : 0

  depends_on = [
    module.eks,
    time_sleep.wait_for_kubernetes,
    data.aws_eks_cluster.cluster,
    data.aws_eks_cluster_auth.cluster,
    helm_release.karpenter,
    kubernetes_manifest.default_nodeclass
  ]

  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "neuron-nodepool"
    }
    spec = {
      template = {
        metadata = {
          labels = {
            owner = "data-engineer"
            instanceType = "neuron"
          }
        }
        spec = {
          nodeClassRef = {
            group = "eks.amazonaws.com"
            kind  = "NodeClass"
            name  = "default"
          }
          taints = [
            {
              key    = "aws.amazon.com/neuron"
              value  = "Exists"
              effect = "NoSchedule"
            }
          ]
          requirements = [
            {
              key      = "eks.amazonaws.com/instance-family"
              operator = "In"
              values   = ["inf2"]
            },
            {
              key      = "karpenter.sh/capacity-type"
              operator = "In"
              values   = ["spot", "on-demand"]
            }
          ]
        }
      }
      limits = {
        cpu    = "1000"
        memory = "1000Gi"
      }
    }
  }
}
resource "kubernetes_manifest" "gpu_nodepool" {
  count = var.enable_auto_mode_node_pool && var.enable_deep_seek_gpu ? 1 : 0
  manifest = {
    apiVersion = "karpenter.sh/v1"
    kind       = "NodePool"
    metadata = {
      name = "gpu-nodepool"
    }
    spec = {
      disruption = {
        consolidationPolicy = "WhenEmpty"
        consolidateAfter = "30s"
      }
      weight = 1
      minReplicas = 2    # Minimum 2 nodes
      maxReplicas = 2    # Maximum 2 nodes
      template = {
        metadata = {
          labels = {
            owner = "data-engineer"
            instanceType = "gpu"
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
              key    = "nvidia.com/gpu"
              value  = "Exists"
              effect = "NoSchedule"
            }
          ]
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
      limits = {
        cpu    = "16"    # Total CPU for 2 nodes (8 CPU each)
        memory = "64Gi"  # Total memory for 2 nodes (32Gi each)
      }
    }
  }

  depends_on = [module.eks]
}

resource "kubernetes_manifest" "neuron_nodepool" {
  count = var.enable_auto_mode_node_pool && var.enable_deep_seek_neuron ? 1 : 0
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

  depends_on = [module.eks]
}
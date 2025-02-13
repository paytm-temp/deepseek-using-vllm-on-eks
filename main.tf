terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    time = {
      source  = "hashicorp/time"
      version = ">= 0.9.1"
    }
    http = {
      source  = "hashicorp/http"
      version = ">= 3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.0"
    }
  }
}

variable "enable_deep_seek_gpu" {
  description = "Enable DeepSeek using GPUs"
  type        = bool
  default     = false
}

variable "enable_deep_seek_neuron" {
  description = "Enable DeepSeek using Neuron"
  type        = bool
  default     = false
}

variable "enable_auto_mode_node_pool" {
  description = "Enable EKS AutoMode NodePool"
  type        = bool
  default     = false
}

locals {
  region   = "ap-south-1"
  vpc_cidr = "10.0.0.0/16"
  name     = "eks-automode"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint = local.name
  }
}


# Define the required providers
provider "aws" {
  region = local.region # Change to your desired region
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
  ignore_annotations = [
    "^karpenter.sh/.*"
  ]
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
  }
  experiments {
    manifest = true
  }
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# Use the Terraform VPC module to create a VPC
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "5.17.0" # Use the latest version available

  name = "${local.name}-vpc"
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# Use the Terraform EKS module to create an EKS cluster
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "20.33.1" # Use the latest version available

  cluster_name    = local.name
  cluster_version = "1.31" # Specify the EKS version you want to use

  cluster_endpoint_public_access           = true
  enable_irsa                              = true
  enable_cluster_creator_admin_permissions = true

  cluster_compute_config = {
    enabled    = true
    node_pools = ["general-purpose"]  # Add back for initial cluster setup
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_addons = {
    vpc-cni = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
  }

  tags = local.tags
}

# Add this after time_sleep
data "aws_eks_cluster" "cluster" {
  name = module.eks.cluster_name

  depends_on = [
    module.eks,
    time_sleep.wait_for_kubernetes
  ]
}

data "aws_eks_cluster_auth" "cluster" {
  name = module.eks.cluster_name

  depends_on = [
    module.eks,
    time_sleep.wait_for_kubernetes
  ]
}

data "http" "wait_for_cluster" {
  url = module.eks.cluster_endpoint

  depends_on = [
    data.aws_eks_cluster.cluster
  ]
}

# Add this after the eks module
resource "time_sleep" "wait_for_kubernetes" {
  depends_on = [module.eks]

  create_duration = "20s"
}

resource "aws_ecr_repository" "chatbot-ecr" {
  name                 = "${local.name}-chatbot"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "neuron-ecr" {
  name                 = "${local.name}-neuron-base"
  image_tag_mutability = "MUTABLE"
}

# Add after the eks module but before the nodepool resources
module "karpenter" {
  source  = "terraform-aws-modules/eks/aws//modules/karpenter"
  version = "20.33.1"

  cluster_name = module.eks.cluster_name

  irsa_oidc_provider_arn          = module.eks.oidc_provider_arn
  irsa_namespace_service_accounts = ["karpenter:karpenter"]
}

# Create the IAM role for Karpenter
resource "aws_iam_role_policy_attachment" "karpenter_policy" {
  role       = module.karpenter.iam_role_name
  policy_arn = aws_iam_policy.karpenter.arn
}

resource "aws_iam_policy" "karpenter" {
  name = "KarpenterControllerPolicy-${local.name}"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:RunInstances",
          "ec2:CreateTags",
          "iam:PassRole",
          "ec2:TerminateInstances",
          "ec2:DescribeLaunchTemplates",
          "ec2:DescribeInstances",
          "ec2:DescribeSecurityGroups",
          "ec2:DescribeSubnets",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeAvailabilityZones",
          "ssm:GetParameter"
        ]
        Resource = ["*"]
      }
    ]
  })
}

resource "helm_release" "karpenter" {
  namespace        = "karpenter"
  create_namespace = true

  name       = "karpenter"
  repository = "oci://public.ecr.aws/karpenter"
  chart      = "karpenter"
  version    = "v0.33.1"

  set {
    name  = "settings.aws.clusterName"
    value = module.eks.cluster_name
  }

  set {
    name  = "settings.aws.clusterEndpoint"
    value = module.eks.cluster_endpoint
  }

  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = module.karpenter.iam_role_arn
  }

  depends_on = [
    module.eks,
    module.karpenter,
    time_sleep.wait_for_kubernetes
  ]
}

# Add this nodeclass manifest
resource "kubernetes_manifest" "default_nodeclass" {
  manifest = {
    apiVersion = "karpenter.k8s.aws/v1beta1"
    kind       = "NodeClass"
    metadata = {
      name = "default"
    }
    spec = {
      amiFamily = "AL2"
      role      = module.karpenter.iam_role_name
      subnetSelectorTerms = [
        {
          tags = {
            "kubernetes.io/role/internal-elb" = "1"
          }
        }
      ]
      securityGroupSelectorTerms = [
        {
          tags = {
            "kubernetes.io/cluster/${module.eks.cluster_name}" = "owned"
          }
        }
      ]
    }
  }

  depends_on = [
    helm_release.karpenter,
    data.http.wait_for_cluster,
    data.aws_eks_cluster.cluster,
    data.aws_eks_cluster_auth.cluster,
    null_resource.wait_for_cluster
  ]
}

# Outputs
output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "ecr_repository_uri" {
  value = aws_ecr_repository.chatbot-ecr.repository_url
}

output "ecr_repository_uri_neuron" {
  value = aws_ecr_repository.neuron-ecr.repository_url
}

# Add this null resource to enforce ordering
resource "null_resource" "wait_for_cluster" {
  depends_on = [
    module.eks,
    time_sleep.wait_for_kubernetes,
    data.http.wait_for_cluster
  ]
}


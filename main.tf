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
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name]
    }
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
    node_pools = ["general-purpose"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  # Add managed node group for Karpenter
  eks_managed_node_groups = {
    gpu = {
      name           = "gpu-node-group"
      instance_types = ["g4dn.2xlarge"]
      min_size      = 2
      max_size      = 2
      desired_size  = 2

      labels = {
        owner       = "data-engineer"
        instanceType = "gpu"
      }

      taints = [{
        key    = "nvidia.com/gpu"
        value  = "Exists"
        effect = "NO_SCHEDULE"
      }]
    }
  }

  tags = local.tags
}


resource "aws_ecr_repository" "chatbot-ecr" {
  name                 = "${local.name}-chatbot"
  image_tag_mutability = "MUTABLE"
}

resource "aws_ecr_repository" "neuron-ecr" {
  name                 = "${local.name}-neuron-base"
  image_tag_mutability = "MUTABLE"
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
# Add Karpenter Helm repository
# resource "helm_release" "karpenter" {
#   namespace        = "karpenter"
#   create_namespace = true
#   name            = "karpenter"
#   repository      = "oci://public.ecr.aws/karpenter"
#   chart           = "karpenter"
#   version         = "v0.33.0"

#   set {
#     name  = "settings.aws.clusterName"
#     value = module.eks.cluster_name
#   }

#   set {
#     name  = "settings.aws.clusterEndpoint"
#     value = module.eks.cluster_endpoint
#   }

#   set {
#     name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
#     value = module.karpenter_irsa.iam_role_arn
#   }
# }

# # Add IAM role for Karpenter
# module "karpenter_irsa" {
#   source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts-eks"
#   version = "~> 5.20"

#   role_name                          = "karpenter-controller-${module.eks.cluster_name}"
#   attach_karpenter_controller_policy = true

#   karpenter_controller_cluster_id = module.eks.cluster_name
#   karpenter_controller_node_iam_role_arns = [
#     module.eks.cluster_iam_role_arn
#   ]
# }


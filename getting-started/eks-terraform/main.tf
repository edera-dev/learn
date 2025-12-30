terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
  required_version = ">= 1.3"
}

# Provider configuration
provider "aws" {
  region = var.region
}

# Local values
locals {
  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version
  node_group_name = "edera-protect-nodes"
}

# Validation: SSH key required when SSH access is enabled
resource "null_resource" "ssh_validation" {
  count = var.enable_ssh_access && var.ssh_key_name == "" ? 1 : 0

  provisioner "local-exec" {
    command = "echo 'Error: ssh_key_name must be provided when enable_ssh_access is true' && exit 1"
  }
}

# Data source for Edera AMI
data "aws_ami" "edera_protect" {
  owners      = [var.edera_account_id]
  most_recent = true

  filter {
    name   = "name"
    values = [
      "edera-protect-v1.*-al2023-amazon-eks-node-${local.cluster_version}-*"
    ]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

# VPC Module
module "vpc" {
  source = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${local.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = ["${var.region}a", "${var.region}b"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway     = true
  enable_vpn_gateway     = false
  enable_dns_hostnames   = true
  enable_dns_support     = true
  map_public_ip_on_launch = true

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = "1"
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = "1"
  }

  tags = {
    Terraform   = "true"
    Environment = "edera-learn"
    Project     = "edera-eks-example"
  }
}

# EKS Module
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.0"

  cluster_name    = local.cluster_name
  cluster_version = local.cluster_version

  cluster_endpoint_public_access  = true
  cluster_endpoint_private_access = true

  # Cluster access entry
  # To add the current caller identity as an administrator
  enable_cluster_creator_admin_permissions = true

  # Security group rules for SSH access
  node_security_group_additional_rules = {
    ingress_ssh = {
      description = "SSH access from anywhere"
      protocol    = "tcp"
      from_port   = 22
      to_port     = 22
      type        = "ingress"
      cidr_blocks = ["0.0.0.0/0"]
    }
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.public_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  # EKS Managed Node Group(s)
  eks_managed_node_groups = {
    edera_protect = {
      name = local.node_group_name

      # Use Edera AMI
      ami_id   = data.aws_ami.edera_protect.id
      ami_type = "AL2023_x86_64_STANDARD"

      instance_types = var.instance_types
      capacity_type  = "ON_DEMAND"

      min_size     = var.min_size
      max_size     = var.max_size
      desired_size = var.desired_size

      # Important: Enable bootstrap user data
      enable_bootstrap_user_data = true

      # Optional SSH access
      key_name = var.enable_ssh_access ? var.ssh_key_name : null

      # Labels for Edera RuntimeClass nodeSelector
      labels = {
        "node-type"   = "al2023"
        "protect-ami" = "true"
        "runtime"     = "edera"  # Required for Edera RuntimeClass
      }

      tags = {
        Name        = "${local.cluster_name}-${local.node_group_name}"
        EderaAMI    = "true"
        Environment = "edera-learn"
        Project     = "edera-eks-example"
      }
    }
  }

  tags = {
    Terraform   = "true"
    Environment = "edera-learn"
    Project     = "edera-eks-example"
  }
}
################################################################################
# EKS Cluster
################################################################################

module "eks" {
  source          = "terraform-aws-modules/eks/aws"
  version         = "~> 20.31"
  cluster_name    = local.name
  cluster_version = "1.31"
  enable_cluster_creator_admin_permissions = true
  cluster_endpoint_public_access           = true

  cluster_addons = {
    coredns    = {}
    kube-proxy = {}
    vpc-cni    = {}
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2_x86_64"
      instance_types = ["t3.large"]
      min_size       = 2
      max_size       = 3
      desired_size   = 2
    }
  }

  tags = local.tags
}


################################################################################
# VPC
################################################################################
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]
  intra_subnets   = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 52)]

  enable_nat_gateway = true
  single_nat_gateway = true

  tags = local.tags
}

resource "helm_release" "splunk_otel_collector" {
  name       = "splunk-otel-collector"
  repository = "https://signalfx.github.io/splunk-otel-collector-chart"
  chart      = "splunk-otel-collector"
  namespace  = "monitoring"
  create_namespace = true
  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "distribution"
    value = "eks"
  }

  set {
    name  = "splunkObservability.accessToken"
    value = var.splunk_access_token
  }

  set {
    name  = "clusterName"
    value = "eks-signalfx"
  }

  set {
    name  = "splunkObservability.realm"
    value = "au0"
  }

  set {
    name  = "gateway.enabled"
    value = "false"
  }

  set {
    name  = "environment"
    value = "lab"
  }

  set {
    name  = "agent.discovery.enabled"
    value = "true"
  }
}


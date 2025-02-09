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

# -------------------------
# Install Splunk OpenTelemetry Collector
# -------------------------
resource "helm_release" "kube_state_metrics" {
  name       = "kube-state-metrics"
  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-state-metrics"
  namespace  = "monitoring"
  create_namespace = true

  values = [
    # Adding podAnnotations to enable Prometheus scraping
    <<-EOT
    podAnnotations:
      prometheus.io/scrape: "true"
      prometheus.io/path: "/metrics"
      prometheus.io/port: "8080"
    EOT
  ]
}

resource "helm_release" "splunk_otel_collector" {
  name       = "splunk-otel-collector"
  repository = "https://signalfx.github.io/splunk-otel-collector-chart"
  chart      = "splunk-otel-collector"
  namespace  = "monitoring"
  create_namespace = true


  set {
    name  = "splunkObservability.realm"
    value = var.splunk_realm
  }

  set {
    name  = "splunkObservability.accessToken"
    value = var.splunk_access_token
  }

  set {
    name  = "clusterName"
    value = local.name
  }
  set {
    name  = "agent.enabled"
    value = "true"
  }
  set {
    name  = "autodetect.prometheus"
    value = "true"
  }
set {
  name  = "agent.config.receivers.prometheus.config.scrape_configs[0].job_name"
  value = "kube-state-metrics"
}

set {
  name  = "agent.config.receivers.prometheus.config.scrape_configs[0].scrape_interval"
  value = "5s"
}

set {
  name  = "agent.config.receivers.prometheus.config.scrape_configs[0].static_configs[0].targets[0]"
  value = "kube-state-metrics.monitoring.svc.cluster.local:8080"
}

  # Enable Kubernetes Cluster Receiver (k8s_cluster)
  set {
    name  = "agent.config.receivers.k8s_cluster.collection_interval"
    value = "60s"
  }

  # Enable Kubelet Stats Receiver
  set {
    name  = "agent.config.receivers.kubeletstats.collection_interval"
    value = "30s"
  }

  set {
    name  = "agent.config.receivers.kubeletstats.auth_type"
    value = "serviceAccount"
  }

  set {
    name  = "agent.config.receivers.kubeletstats.metric_groups[0]"
    value = "container"
  }

  set {
    name  = "agent.config.receivers.kubeletstats.metric_groups[1]"
    value = "pod"
  }

  set {
    name  = "agent.config.receivers.kubeletstats.metric_groups[2]"
    value = "node"
  }

  set {
    name  = "agent.config.receivers.kubeletstats.metric_groups[3]"
    value = "volume"
  }
  # Configure Exporter
  set {
    name  = "agent.config.exporters.otlp.endpoint"
    value = "https://ingest.au0.signalfx.com:443"
  }
  set {
    name  = "distribution"
    value = "eks"
  }

  set {
    name  = "cloudProvider"
    value = "aws"
  }

  set {
    name  = "agent.config.exporters.otlp.headers.X-SF-Token"
    value = var.splunk_access_token
  }
# Add resourcedetection processor
set {
  name  = "agent.config.processors.resourcedetection.detectors[0]"
  value = "env"
}

set {
  name  = "agent.config.processors.resourcedetection.detectors[1]"
  value = "system"
}

set {
  name  = "agent.config.processors.resourcedetection.override"
  value = "false"
}

# Add resourcedetection to the pipeline
set {
  name  = "agent.config.service.pipelines.metrics.processors[0]"
  value = "resourcedetection"
}

set {
  name  = "agent.config.service.pipelines.metrics.processors[1]"
  value = "batch"
}

  # Configure the service pipeline
  set {
    name  = "agent.config.service.pipelines.metrics.receivers[0]"
    value = "kubeletstats"
  }

  set {
    name  = "agent.config.service.pipelines.metrics.receivers[1]"
    value = "k8s_cluster"
  }
  set {
    name  = "agent.config.service.pipelines.metrics.receivers[2]"
    value = "prometheus"
  }


  set {
    name  = "agent.config.service.pipelines.metrics.exporters[0]"
    value = "signalfx"
  }


}



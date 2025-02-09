data "kubernetes_service" "argocd_server" {
  metadata {
    name      = "argocd-server"
    namespace = "argocd"
  }
  depends_on = [module.eks]  # Ensures the EKS cluster is created first
}

#provider "argocd" {
 #  core = true
# server_addr = "${data.kubernetes_service.argocd_server.status.0.load_balancer.0.ingress.0.hostname}:80"
# username = "admin"
# password = "$2a$12$GQEMrXciyO5emNhJXMhBneWjABXbYstJ6Z3XeVofZEHv1DciAPJKe"
#}

resource "helm_release" "argocd" {
  name       = "argocd"
  namespace  = "argocd"
  create_namespace = true

  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = "7.7.23"

  values = [
    <<EOF
    server:
      service:
        type: LoadBalancer
    configs:
      secret:
         createSecret: true
         argocdServerAdminPassword: "$2a$12$GQEMrXciyO5emNhJXMhBneWjABXbYstJ6Z3XeVofZEHv1DciAPJKe"  # Use bcrypt hash

EOF
  ]
}

resource "helm_release" "nginx_ingress" {
  name       = "nginx-ingress"
  namespace  = "ingress-nginx"
  repository = "https://kubernetes.github.io/ingress-nginx"
  chart      = "ingress-nginx"
  version    = "4.12.0"  # Make sure to use the latest stable version

  create_namespace = true

  values = [
    <<EOF
controller:
  service:
    externalTrafficPolicy: Local
    type: LoadBalancer
EOF
  ]
}

# Create Dashboard Group
resource "signalfx_dashboard_group" "k8s_monitoring" {
  name = "Kubernetes Monitoring"
}




resource "signalfx_dashboard" "argocd_dashboard" {
  name        = "ArgoCD Events & Metrics"
  description = "Monitor ArgoCD sync events and pod CPU utilization"
  dashboard_group = signalfx_dashboard_group.k8s_monitoring.id

  # 🎛️ Dropdown for selecting cluster (empty by default)
  variable {
    property       = "k8s.cluster.name"
    alias          = "Cluster"
    values         = []  # No default values, user must select manually
 }

  # 🎛️ Dropdown for selecting app (empty by default)
  variable {
    property       = "app"
    alias          = "App Name"
    values         = []  # No default values, user must select manually
    value_required = false
  }

  # Add ArgoCD Sync Events chart to the dashboard
  chart {
    chart_id = signalfx_event_feed_chart.argocd_sync_events.id
    column   = 0
    row      = 0
    width    = 3
    height   = 1
  }
  chart {
    chart_id = signalfx_single_value_chart.desired_pods.id
    column   = 3
    row      = 0
    width    = 3
    height   = 1
  }

  chart {
    chart_id = signalfx_single_value_chart.available_pods.id
    column   = 3
    row      = 1
    width    = 3
    height   = 1
  }

  chart {
    chart_id = signalfx_time_chart.cpu_usage.id
    column   = 6
    row      = 0
    width    = 6
    height   = 1
  }
  chart {
    chart_id = signalfx_time_chart.memory_resources.id
    column   = 6
    row      = 3
    width    = 6
    height   = 1
  }

  chart {
    chart_id = signalfx_list_chart.network_errors.id
    column   = 0
    row      = 3
    width    = 6
    height   = 1
  }

  chart {
    chart_id = signalfx_time_chart.network_io.id
    column   = 0
    row      = 4
    width    = 6
    height   = 1
  }
  chart {
    chart_id = signalfx_time_chart.volume_overview.id
    column   = 0
    row      = 5
    width    = 6
    height   = 1
  }

  chart {
    chart_id = signalfx_time_chart.filesystem_usage.id
    column   = 0
    row      = 2
    width    = 6
    height   = 1
  }

  chart {
    chart_id = signalfx_time_chart.memory_usage.id
    column   = 6
    row      = 2
    width    = 6
    height   = 1
  }

  chart {
    chart_id = signalfx_time_chart.cpu_resources.id
    column   = 6
    row      = 1
    width    = 6
    height   = 1
  }
}

# 📌 Event Feed Chart: ArgoCD Sync Events
resource "signalfx_event_feed_chart" "argocd_sync_events" {
  name       = "ArgoCD Sync Events"
 # time_range = "-1h"

  program_text = "A = events(eventType='sync_status', filter=filter('k8s.cluster.name', '$${k8s.cluster.name}') and filter('app', '$${app}')).publish(label='ArgoCD Sync Event')"
}


resource "signalfx_single_value_chart" "available_pods" {
  name        = "# Available pods"
  description = ""

  program_text = <<EOT
A = data('k8s.deployment.available', filter=filter('app', '{$app}')).sum().publish(label='A')
EOT

  max_precision   = 4
  unit_prefix     = "Metric"
  color_by        = "Metric"
  secondary_visualization = "None"
  show_spark_line = false


}
# Chart: Desired Pods
resource "signalfx_single_value_chart" "desired_pods" {
  name        = "# Desired pods"
  description = ""

  program_text = <<EOT
A = data('k8s.deployment.desired', filter=filter('app', '{$app}')).sum().publish(label='A')
EOT

  max_precision   = 4
  unit_prefix     = "Metric"
  color_by        = "Metric"
  secondary_visualization = "None"
  show_spark_line = false

}

# Chart: CPU Usage
resource "signalfx_time_chart" "cpu_usage" {
  name        = "CPU usage (CPU units)"
  description = "CPU utilization over time"

  program_text = <<EOT
A = data('container_cpu_utilization', filter=filter('app', '{$app}')).sum().publish(label='A')
B = events(eventType='sync_status', filter=filter('k8s.cluster.name', '{$k8s.cluster.name}') and filter('app', '{$app}')).publish(label='ArgoCD Sync Event')
C = data('container.cpu.time', filter=filter('app', '{$app}')).sum().publish(label='C')
EOT

  unit_prefix = "Metric"
  color_by    = "Metric"
  stacked     = false
  show_event_lines = false

}


# ===============================
# Memory Resource Usage Chart
# ===============================
resource "signalfx_time_chart" "memory_resources" {
  name        = "Memory Resource (bytes)"
  description = "Shows memory limits and requests for Kubernetes containers"

  program_text = <<EOF
A = data('k8s.container.memory_limit', filter=filter('app', '{$app}')).publish(label='Memory limit')
B = data('k8s.container.memory_request', filter=filter('app', '{$app}')).publish(label='Memory request')
EOF

  unit_prefix      = "Metric"
}

# ===============================
# Network Errors Chart
# ===============================
resource "signalfx_list_chart" "network_errors" {
  name        = "# Network Errors"
  description = "Tracks network errors received and transmitted"

  program_text = <<EOF
A = data('k8s.pod.network.errors', filter=filter('app', '{$app}') and filter('direction', 'receive')).publish(label='Network errors received')
B = data('k8s.pod.network.errors', filter=filter('app', '{$app}') and filter('direction', 'transmit')).publish(label='Network errors transmitted')
EOF

  unit_prefix      = "Metric"
  color_by    = "Metric"

}

# ===============================
# Network I/O Chart
# ===============================
resource "signalfx_time_chart" "network_io" {
  name        = "Network I/O (bytes)"
  description = "Shows network traffic for Kubernetes deployments"

  program_text = <<EOF
A = data('k8s.pod.network.io', filter=filter('k8s.workload.kind', 'Deployment') and filter('direction', 'receive')).sum(by=['k8s.deployment.name', 'k8s.cluster.name', 'k8s.namespace.name']).publish(label='Network I/O receive')
B = data('k8s.pod.network.io', filter=filter('k8s.workload.kind', 'Deployment') and filter('direction', 'transmit')).sum(by=['k8s.deployment.name', 'k8s.cluster.name', 'k8s.namespace.name']).publish(label='Network I/O transmit')
EOF

  unit_prefix      = "Metric"
}



resource "signalfx_time_chart" "volume_overview" {
  name        = "Volume overview (bytes)"
  description = ""

  program_text = <<EOF
A = data('k8s.volume.capacity', filter=filter('app', '{$app}')).publish(label='Volume capacity')
B = data('k8s.volume.available', filter=filter('app', '{$app}')).publish(label='Volume available')
EOF

  unit_prefix = "Metric"
}

resource "signalfx_time_chart" "filesystem_usage" {
  name        = "File system usage (bytes)"
  description = ""

  program_text = <<EOF
A = data('container.filesystem.usage', filter=filter('app', '{$app}')).publish(label='File system usage')
EOF

  unit_prefix = "Metric"
}

resource "signalfx_time_chart" "memory_usage" {
  name        = "Memory usage (bytes)"
  description = ""

  program_text = <<EOF
A = data('container.memory.usage', filter=filter('app', '{$app}')).publish(label='Memory usage')
EOF

  unit_prefix = "Metric"
}

resource "signalfx_time_chart" "cpu_resources" {
  name        = "CPU resources (CPU units)"
  description = ""

  program_text = <<EOF
A = data('k8s.container.cpu_limit', filter=filter('app', '{$app}')).publish(label='CPU limit')
B = data('k8s.container.cpu_request', filter=filter('app', '{$app}')).publish(label='CPU requested')
EOF

  unit_prefix = "Metric"
}


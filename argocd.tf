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
    width    = 12
    height   = 6
  }
}

# 📌 Event Feed Chart: ArgoCD Sync Events
resource "signalfx_event_feed_chart" "argocd_sync_events" {
  name       = "ArgoCD Sync Events"
 # time_range = "-1h"

  program_text = "A = events(eventType='sync_status', filter=filter('k8s.cluster.name', '$${k8s.cluster.name}') and filter('app', '$${app}')).publish(label='ArgoCD Sync Event')"
}

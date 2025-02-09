
<!-- x-release-please-start-version -->
  ```
    Version : '0.1.11'
  ```
<!-- x-release-please-end -->
# ArgoCD & Splunk Observability (SignalFx) Integration

This guide outlines the steps to deploy an **Nginx application** using **ArgoCD**, configure a **webhook notification system**, and send events to **Splunk Observability (SignalFx)**.

## Steps

### 1. Apply Terraform Configuration
Ensure Terraform is properly configured and apply the configuration:

```sh
terraform apply
```

### 2. Deploy ArgoCD Application and Webhook Configuration
Apply the necessary Kubernetes manifests:

```sh
kubectl apply -f argo.yaml
kubectl apply -f hook.yaml
```

- `argo.yaml` deploys the **Nginx application** via ArgoCD.
- `hook.yaml` sets up the **webhook** to send ArgoCD events to **Splunk Observability**.

### 3. Annotate the Application to Send Events to the Webhook
To enable event notifications, annotate the ArgoCD application:

```sh
kubectl annotate application nginx -n argocd notifications.argoproj.io/subscribe.on-sync.signalfx=""
```

This annotation ensures that **ArgoCD events** (e.g., sync events) are sent to the configured webhook.

### 4. Verify ArgoCD Notifications Controller Logs
To confirm that notifications are being sent, check the logs of the ArgoCD notifications controller:

```sh
kubectl logs -n argocd deployment/argocd-notifications-controller -f
```

If events are being processed correctly, you should see logs indicating successful webhook calls.

### 5. Check SignalFx Dashboard
Go to **Splunk Observability (SignalFx)** and check the dashboard for events.

- Filter events to verify that ArgoCD notifications are being received and processed.
- If the event is not visible, check the webhook logs in ArgoCD and ensure the configuration is correct.

### 6. Send a Custom Property to SignalFx (Optional)
You can manually send **custom metadata** (e.g., cluster name) to **Splunk Observability (SignalFx)** using a **cURL request**:

```sh
curl -X POST "https://ingest.au0.signalfx.com/v2/datapoint" \
     -H "Content-Type: application/json" \
     -H "X-SF-Token: <token>" \
     -d '{
         "gauge": [
             {
                 "metric": "cluster1.name",
                 "dimensions": { "k8s.cluster.name": "dev" },
                 "value": 1
             }
         ]
     }'
```

Replace `<token>` with your **Splunk Observability API token**.

## Conclusion
By following these steps, your ArgoCD deployment will send events to **Splunk Observability (SignalFx)**, allowing you to monitor deployments in real-time. 🚀



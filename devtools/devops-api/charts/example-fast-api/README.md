# FastAPI Helm Chart

A Helm chart for deploying a FastAPI-based API service, with optional integration for Vault secrets and Prometheus monitoring.

---


## 📦 Chart Details

- **Chart Name**: `fastapi-api`
- **Purpose**: Deploys a containerized FastAPI API
- **Supports**:
  - Custom environment variables
  - Vault secret injection (via External Secrets Operator)
  - Prometheus `ServiceMonitor`
  - Configurable image and replica count

---


## 🚀 Usage

### Install the chart

```bash
helm install testapi-ex ./path-to-chart -f values.yaml
```


# ⚙️ Configuration

The following table lists configurable parameters of the FastAPI Helm chart and their default values:

| Parameter | Description | Default |
|----------|-------------|---------|
| `releasename` | Release name override | `testapi` |
| `replicaCount` | Number of pod replicas | `1` |
| `image.repository` | Container image name | `dns-api` |
| `image.tag` | Image tag to deploy | `"7.0"` |
| `image.pullPolicy` | Image pull policy | `IfNotPresent` |
| `resources` | Resource limits/requests for the container | `{}` |
| `env` | Environment variables to inject into the container | Custom key-value pairs |
| `servicemonitor.enabled` | Enable creation of a Prometheus `ServiceMonitor` resource | `true` |
| `servicemonitor.interval` | Metrics scrape interval | `30s` |
| `servicemonitor.release` | Prometheus release label for matching `ServiceMonitor` | `my-prometheus-operator` |
| `vault.enabled` | Enable Vault integration via External Secrets Operator | `true` |
| `vault.clusterSecretStore` | Name of the `ClusterSecretStore` to reference | `vault-cluster-secret-store` |
| `vault.secrets` | List of secrets to expose as environment variables using External Secrets | `[]` |

To override any of these values, provide a custom `values.yaml` or use the `--set` flag when installing or upgrading the chart.


# 🔐 Vault Secret Integration

This Helm chart supports integration with **HashiCorp Vault** via the [External Secrets Operator (ESO)](https://external-secrets.io/).

When enabled, secrets can be securely fetched from Vault and injected into your application as environment variables.

---


## ✅ Requirements

- [External Secrets Operator (ESO)](https://external-secrets.io/)
- A configured `ClusterSecretStore` resource pointing to your Vault instance
- Vault properly unsealed and accessible from the cluster

---


## 🔧 Configuration in `values.yaml`

To enable Vault secret injection:

```yaml
vault:
  enabled: true
  clusterSecretStore: vault-cluster-secret-store
  secrets:
    - secretKey: AWX_TOKEN
      remoteRef:
        key: ds/awx
        property: awx_token
    - secretKey: AWX_HOST
      remoteRef:
        key: ds/awx
        property: awx_host
```


## 📊 Prometheus Monitoring Integration

This Helm chart supports integration with **Prometheus** by optionally creating a `ServiceMonitor` resource. This allows Prometheus (typically deployed via [kube-prometheus-stack](https://github.com/prometheus-community/helm-charts/tree/main/charts/kube-prometheus-stack)) to scrape metrics from your FastAPI application.

---


## 📈 Requirements

- Prometheus Operator installed (e.g., via `kube-prometheus-stack`)
- The `release` label used by your Prometheus installation must match the value in `servicemonitor.release`
- Your FastAPI application must expose a `/metrics` endpoint (e.g., via Prometheus client libraries like `prometheus_fastapi_instrumentator`)

---

## 🔧 Configuration in `values.yaml`

To enable Prometheus integration:

```yaml
servicemonitor:
  enabled: true
  interval: 30s
  release: my-prometheus-operator
```


# 📁 Helm Chart Structure

This document outlines the directory structure of the Helm chart used to deploy the FastAPI-based application.

---

## 📄 File Descriptions

| File | Description |
|------|-------------|
| `Chart.yaml` | Contains metadata about the chart: name, version, dependencies, etc. |
| `values.yaml` | Defines default configuration values used by templates. Can be overridden during installation. |
| `templates/deployment.yaml` | Kubernetes Deployment resource for the FastAPI app. |
| `templates/service.yaml` | Kubernetes Service to expose the FastAPI app. |
| `templates/servicemonitor.yaml` | Optional: Prometheus ServiceMonitor for metrics scraping. Enabled via values. |
| `templates/externalsecret.yaml` | Optional: ExternalSecret to inject Vault secrets. Enabled via values. |

---

## 🛠 Usage

To render the manifests without installing:

```bash
helm template <release-name> ./path-to-chart -f values.yaml

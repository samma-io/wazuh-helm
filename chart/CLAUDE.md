# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Helm chart for deploying Wazuh (SIEM/XDR) on Kubernetes. It is a static, single-replica setup intended for development and testing — not production. All resources are hardcoded to the `wazuh` namespace.

## Prerequisites

The cluster must have these installed before deploying this chart:
- **cert-manager** — all TLS certificates are managed via cert-manager
- **A default StorageClass** — PVCs are created automatically using it

## Deploy / Upgrade

```bash
# From the chart/ directory
helm upgrade --install wazuh . --namespace wazuh --create-namespace
```

## Lint / Template Validation

```bash
helm lint .
helm template wazuh . --namespace wazuh
```

## Architecture

The chart deploys four StatefulSets, all in the `wazuh` namespace:

| Component | StatefulSet | Key Ports |
|---|---|---|
| **Wazuh Indexer** (OpenSearch) | `wazuh-indexer` | 9200, 9300 |
| **Wazuh Manager Master** | `wazuh-manager-master` | 1515 (registration), 1516 (cluster), 55000 (API) |
| **Wazuh Manager Worker** | `wazuh-manager-worker-0` | 1514 (agents), 1516 (cluster) |
| **Wazuh Dashboard** (OpenSearch Dashboards) | `wazuh-dashboard` | 5601 |

### Certificate Chain

`templates/certs/certmanager-certs.yaml` sets up the full PKI:
1. A self-signed `Issuer` (`wazuh-issuer`) creates a root CA certificate (`wazuh-rootca-certificate`)
2. A CA `Issuer` (`wazuh-rootca-issuer`) issues component certificates: `wazuh-admin`, `wazuh-indexer`, `wazuh-manager`, `wazuh-worker`, `wazuh-dashboard`
3. Each StatefulSet mounts its cert from the corresponding Secret (e.g. `secretName: wazuh-manager`)
4. The root CA (`wazuh-rootca-certificate` secret, key `ca.crt`) is also mounted into every component as the trust anchor

### Init Containers

Every StatefulSet uses an init container (`volume-mount-hack`) to fix ownership/permissions on PVC mount points before the main container starts. Manager components use the `wazuh/wazuh-manager` image for init (to get the correct `wazuh` user); Indexer and Dashboard use `busybox`.

### Networking

- **wazuh-cluster** (headless ClusterIP) — used as `serviceName` for all StatefulSets to enable pod-to-pod discovery
- **wazuh** (NodePort) — exposes port 1515 (registration) and 55000 (API) externally
- **wazuh-manager** (ClusterIP) — internal access to master ports 1515, 1516, 55000
- Dashboard is exposed via NodePort (see `wazuh-dashboard-svc.yaml`)

### values.yaml

Only two values are currently used:
- `cluster` — environment identifier (int)
- `wazuh.tag` — Docker image tag for all Wazuh images (e.g. `4.14.0`)

All images are `wazuh/wazuh-{component}:{{ .Values.wazuh.tag }}`.

### Hardcoded Credentials

Credentials are currently baked into the StatefulSet env vars (not Secrets):
- Indexer: `admin` / `admin`
- Dashboard: `kibanaserver` / `kibanaserver`
- Wazuh API: `wazuh-wui` / `MyS3cr37P450r.*-`
- Agent registration key: mounted from ConfigMap `wazuh-register-key`

### Storage

| PVC | Size | Used by |
|---|---|---|
| `wazuh-indexer-data` | 50Gi | Indexer data |
| `wazuh-manager-master` | 10Gi | Master ossec data |
| `wazuh-manager-filebeat` | 5Gi | Master filebeat state |
| `wazuh-worker-0` | 20Gi | Worker ossec data |
| `wazuh-worker-filebeat` | 5Gi | Worker filebeat state |
| `wazuh-dashboard-data` | 5Gi | Dashboard config/assets |

All nodes are pinned to `kubernetes.io/arch: amd64`.

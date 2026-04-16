# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is a Helm chart for deploying Wazuh (SIEM/XDR) on Kubernetes with optional Keycloak OIDC integration. It is a single-replica setup deployed via ArgoCD. All resources target the `wazuh` namespace.

## Prerequisites

The cluster must have these installed before deploying:
- **cert-manager** — all TLS certificates managed via cert-manager
- **Traefik** — ingress controller (used when `ingress.enabled: true`)
- **CloudNativePG operator** — required when `keycloak.enabled: true`

## Deploy / Upgrade

```bash
# From the chart/ directory
helm upgrade --install wazuh . --namespace wazuh --create-namespace

# With Keycloak and ingress
helm upgrade --install wazuh . --namespace wazuh --create-namespace \
  --set keycloak.enabled=true \
  --set ingress.enabled=true \
  --set ingress.host=wazuh.yourdomain.com
```

## Lint / Template Validation

```bash
helm lint .
helm template wazuh . --namespace wazuh --set keycloak.enabled=true --set ingress.enabled=true --set ingress.host=wazuh.example.com
```

## Architecture

The chart deploys four StatefulSets plus optional Keycloak, all in the `wazuh` namespace:

| Component | Kind | Key Ports |
|---|---|---|
| **Wazuh Indexer** (OpenSearch) | StatefulSet | 9200, 9300 |
| **Wazuh Manager Master** | StatefulSet | 1515 (registration), 1516 (cluster), 55000 (API) |
| **Wazuh Manager Worker** | StatefulSet | 1514 (agents), 1516 (cluster) |
| **Wazuh Dashboard** (OpenSearch Dashboards) | StatefulSet | 5601 |
| **Keycloak** (optional) | Deployment | 8080 |
| **CNPG PostgreSQL** (optional, for Keycloak) | Cluster | 5432 |

### Certificate Chain

`templates/certs/certmanager-certs.yaml` sets up the full PKI:
1. Self-signed `Issuer` (`wazuh-issuer`) creates root CA (`wazuh-rootca-certificate`)
2. CA `Issuer` (`wazuh-rootca-issuer`) issues: `wazuh-admin`, `wazuh-indexer`, `wazuh-manager`, `wazuh-worker`, `wazuh-dashboard`
3. `wazuh-admin` cert uses `privateKey.encoding: PKCS8` — required by OpenSearch 2.x securityadmin
4. The root CA secret (`ca.crt` key) is mounted as trust anchor in every component

### Keycloak OIDC integration

When `keycloak.enabled: true`, the following are created:
- `keycloak-cnpg-cluster.yaml` — CNPG PostgreSQL cluster (`keycloak-pg`), service `keycloak-pg-rw`
- `keycloak-secret.yaml` — holds admin credentials and DB password; CNPG bootstrap reads `username`/`password` keys
- `keycloak-deployment.yaml` — Keycloak pod with `KC_HTTP_RELATIVE_PATH` and `KC_HOSTNAME_PATH` set to `keycloak.path` (default `/login`)
- `keycloak-realm-configmap.yaml` — seeds the `wazuh` realm on first boot via `--import-realm`
- `keycloak-svc.yaml` — ClusterIP on port 80
- `opensearch-security-config.yaml` — OpenSearch `config.yml` enabling both basic auth and OIDC auth domains
- `keycloak-securityadmin-job.yaml` — ArgoCD `Sync` hook Job that applies `config.yml` to the live OpenSearch index via `securityadmin.sh`

#### Realm JSON design

The `wazuh-realm.json` ConfigMap defines:
- One custom `clientScope` named `groups` — uses `oidc-group-membership-mapper` to emit group membership as `groups` claim
- One client `wazuh` with `defaultClientScopes: ["groups"]` only — standard Keycloak scopes (profile, email, etc.) are NOT included because they're not defined in the realm import
- Three protocol mappers on the client: `audience` (adds `wazuh` to aud claim), `preferred_username` (maps username → preferred_username claim), `email`
- Three groups: `admin`, `security_analytics_full_access`, `security_analytics_read_access`

Do NOT add standard Keycloak scopes (profile, email, roles, web-origins, acr) to `defaultClientScopes` — they don't exist in this realm and Keycloak will reject any login request that references them.

#### Ingress routing (Traefik)

Two routes on the same host:
- `PathPrefix('/login')` priority **100** → Keycloak (HTTP backend, Traefik terminates TLS)
- bare `Host()` → Wazuh Dashboard (HTTPS backend, `scheme: https`)

Priority 100 is required. Traefik auto-calculates priority from rule length for routes without explicit priority; the bare Host rule would otherwise win.

The dashboard's OIDC callback is `/auth/openid/login` — this hits the bare Host rule and goes to the dashboard correctly, with no conflict.

#### securityadmin hook

The Job uses the ArgoCD `Sync` hook (not Helm hooks, which ArgoCD SSA doesn't execute). The initContainer polls the indexer until ready; the main container runs `securityadmin.sh` with the PKCS8 `tls.key` from the `wazuh-admin` secret.

`wazuh-workers` LoadBalancer service has no external IP in environments without a cloud LB provisioner. This keeps the app in `Degraded` health in ArgoCD but does not affect functionality.

### Networking

- **wazuh-cluster** (headless ClusterIP) — StatefulSet pod discovery
- **wazuh** (NodePort) — agent registration (1515) and API (55000)
- **wazuh-workers** (LoadBalancer) — agent events (1514), AWS NLB annotation
- **wazuh-workers-nodeport** (NodePort) — agent events fallback
- **wazuh-manager** (ClusterIP) — internal master access
- **keycloak** (ClusterIP port 80) — Keycloak HTTP, Traefik proxies to it

### Credentials

All credentials are in `values.yaml` and templated into env vars and Secrets. The OpenSearch internal user hashes in `internal_users.yml` (inside `wazuh-indexer-conf` ConfigMap) are pre-computed for the defaults. If `credentials.indexer.password` changes, rerun securityadmin.sh to update the hash.

### Storage

| PVC | Default size | Component |
|---|---|---|
| `wazuh-indexer-data` | 50Gi | Indexer |
| `wazuh-manager-master` | 50Gi | Manager master |
| `wazuh-manager-filebeat` | 5Gi | Master Filebeat |
| `wazuh-worker-0` | 50Gi | Manager worker |
| `wazuh-worker-filebeat` | 5Gi | Worker Filebeat |
| `wazuh-dashboard-data` | 5Gi | Dashboard |
| `keycloak-pg` | 10Gi | CNPG PostgreSQL |

All pods are pinned to `kubernetes.io/arch: amd64` via `nodeSelector`.

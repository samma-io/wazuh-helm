# Wazuh on Kubernetes

A Helm chart for deploying the [Wazuh](https://wazuh.com) security platform on Kubernetes. Designed for development and testing environments with a single-replica setup for each component.

> **Note:** This chart is intended for dev/test use. Production deployments require tuning of credentials, storage, resource limits, and HA configuration.

---

## Prerequisites

The following must be installed in the cluster before deploying:

- **cert-manager** — manages all internal TLS certificates via self-signed PKI
- **A default StorageClass** — PVCs are provisioned automatically
- **Traefik** *(optional)* — required only if `ingress.enabled: true`
- **CloudNativePG operator** *(optional)* — required only if `keycloak.enabled: true`

---

## MFA and compliance requirements

Wazuh's built-in authentication (username/password stored as bcrypt hashes in OpenSearch) does not support multi-factor authentication. For environments subject to compliance frameworks that mandate MFA — such as ISO 27001, SOC 2, or NIS2 — the default auth is not sufficient on its own.

**Adding Keycloak as an OIDC identity provider is the recommended path to MFA.** Keycloak supports TOTP, WebAuthn, and integration with external identity providers (Entra ID, Okta, Google Workspace). Once Keycloak is in place, users log in through Keycloak's login page and the Wazuh Dashboard accepts the resulting OIDC token — the internal OpenSearch user database is only used by internal service accounts.

This chart includes a built-in Keycloak integration. See the [Keycloak section](#keycloak-oidc-identity-provider) below.

---

## Installation

### Quick start

```bash
helm upgrade --install wazuh ./chart \
  --namespace wazuh \
  --create-namespace
```

### With a custom values file

```bash
helm upgrade --install wazuh ./chart \
  --namespace wazuh \
  --create-namespace \
  -f my-values.yaml
```

### With ingress and TLS

```bash
helm upgrade --install wazuh ./chart \
  --namespace wazuh \
  --create-namespace \
  --set ingress.enabled=true \
  --set ingress.host=wazuh.yourdomain.com \
  --set ingress.clusterIssuer=letsencrypt-prod
```

When ingress is enabled, cert-manager provisions a publicly-trusted TLS certificate via the specified `ClusterIssuer`. Traefik forwards HTTPS traffic to the dashboard, which also has its own internal TLS (managed by the Wazuh internal PKI).

### With a specific StorageClass

```bash
helm upgrade --install wazuh ./chart \
  --namespace wazuh \
  --create-namespace \
  --set persistence.storageClass=longhorn
```

---

## Architecture

The chart deploys four StatefulSets in the target namespace:

| Component | Image | Key ports |
|---|---|---|
| **Wazuh Indexer** (OpenSearch) | `wazuh/wazuh-indexer` | 9200 (API), 9300 (transport) |
| **Wazuh Manager Master** | `wazuh/wazuh-manager` | 1515 (registration), 1516 (cluster), 55000 (API) |
| **Wazuh Manager Worker** | `wazuh/wazuh-manager` | 1514 (agents), 1516 (cluster) |
| **Wazuh Dashboard** | `wazuh/wazuh-dashboard` | 5601 |

All images are versioned together via `wazuh.tag`.

### Certificates

cert-manager creates a self-signed root CA and issues component certificates for indexer, manager, worker, and dashboard. All internal pod-to-pod traffic is TLS-encrypted using this PKI.

### Alert sharing

Both manager pods expose `/var/ossec/logs/alerts/` as a shared `emptyDir` volume named `wazuh-alerts`. Sidecar containers added to the manager pods can mount this volume to consume alert files in real time:

```yaml
- name: wazuh-alerts
  mountPath: /alerts
  readOnly: true
```

### Agent connectivity

Agent traffic uses TCP, not HTTP, and cannot be routed through an Ingress:

| Purpose | Service | Type |
|---|---|---|
| Agent registration | `wazuh` | NodePort (1515) |
| Agent events | `wazuh-workers` | LoadBalancer (1514) |
| Manager API | `wazuh` | NodePort (55000) |

---

## Access

### Dashboard (with ingress)

```
https://<ingress.host>
```

### Dashboard (without ingress, port-forward)

```bash
kubectl port-forward -n wazuh svc/wazuh-dashboard 5601:5601
```

Then open: `https://localhost:5601`

### Manager API (port-forward)

```bash
kubectl port-forward -n wazuh svc/wazuh 55000:55000
```

### Default credentials

| Service | Username | Password (default) |
|---|---|---|
| Dashboard / Indexer | `admin` | `admin` |
| Dashboard internal | `kibanaserver` | `kibanaserver` |
| Wazuh API | `wazuh-wui` | `MyS3cr37P450r.*-` |

> **Important:** The Wazuh Indexer (OpenSearch) stores credentials as bcrypt hashes in `internal_users.yml`. Changing `credentials.indexer.password` or `credentials.dashboard.password` in values only updates env vars — you must also update the hashes by running `securityadmin.sh` inside the indexer pod.

---

## Keycloak OIDC identity provider

Setting `keycloak.enabled: true` deploys Keycloak backed by a CloudNativePG PostgreSQL cluster and wires it into the Wazuh Dashboard as an OpenID Connect identity provider. Users log in via Keycloak; the internal OpenSearch user database is only used by service accounts.

This is the recommended setup for any environment where MFA is required.

### Prerequisites

Install the [CloudNativePG operator](https://cloudnative-pg.io/documentation/current/installation_upgrade/) in the cluster before enabling Keycloak:

```bash
kubectl apply --server-side -f \
  https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.24/releases/cnpg-1.24.0.yaml
```

### Enabling Keycloak

Add to your values file:

```yaml
keycloak:
  enabled: true
  tag: "23.0.6"
  realm: wazuh
  clientSecret: "CHANGE_ME"      # set to a random string, copy into Keycloak client later
  admin:
    username: admin
    password: "CHANGE_ME"
  db:
    name: keycloak
    username: keycloak
    password: "CHANGE_ME"
    storageSize: 10Gi
```

On first install, Keycloak imports a pre-seeded realm (`wazuh`) containing:

- A `wazuh` OIDC client configured for the dashboard
- A `groups` scope that passes group membership as an OIDC claim
- Three groups: `admin`, `security_analytics_full_access`, `security_analytics_read_access`

Keycloak is exposed at `https://<ingress.host>/auth`. The Wazuh Dashboard at `https://<ingress.host>` redirects unauthenticated users there automatically.

### Post-install: create your first user

1. Open `https://<ingress.host>/auth` and log in with the admin credentials from values
2. Switch to the `wazuh` realm
3. Create a user under **Users** and assign them to the `admin` group
4. Enable an MFA credential (TOTP or WebAuthn) under the user's **Credentials** tab
5. Log out, then open `https://<ingress.host>` — you should be redirected to Keycloak and prompted for MFA

### Connecting an external identity provider

To use Entra ID, Okta, or Google Workspace instead of local Keycloak users:

1. In the `wazuh` realm, go to **Identity Providers** and add your provider
2. Map the provider's groups or roles to the Keycloak groups above using **Identity Provider Mappers**

Users from the external IdP then log in through Keycloak, which handles MFA enforcement according to the realm's authentication flows.

---

## Values Reference

### Image

| Value | Default | Description |
|---|---|---|
| `wazuh.tag` | `"4.14.0"` | Image tag for all Wazuh components |

### General

| Value | Default | Description |
|---|---|---|
| `createNamespace` | `false` | Create the namespace as part of the release (alternative to `--create-namespace`) |
| `nodeSelector` | `kubernetes.io/arch: amd64` | Node selector applied to all StatefulSets. Set to `{}` to disable |

### Credentials

| Value | Default | Description |
|---|---|---|
| `credentials.indexer.username` | `admin` | OpenSearch admin username |
| `credentials.indexer.password` | `admin` | OpenSearch admin password |
| `credentials.api.username` | `wazuh-wui` | Wazuh API service account username |
| `credentials.api.password` | `MyS3cr37P450r.*-` | Wazuh API service account password |
| `credentials.dashboard.username` | `kibanaserver` | Dashboard internal OpenSearch username |
| `credentials.dashboard.password` | `kibanaserver` | Dashboard internal OpenSearch password |
| `credentials.agentRegistration` | `CUSTOM_PASSWORD` | Agent registration password (`authd.pass`) |
| `credentials.clusterKey` | `c98b6ha9b6169zc5f67rae55ae4z5647` | Wazuh cluster key — must be identical on master and all workers |

### Certificates

| Value | Default | Description |
|---|---|---|
| `certs.duration` | `2160h` | Lifetime of internal component certificates (90 days) |
| `certs.renewBefore` | `360h` | How early cert-manager renews certificates (15 days) |

### Persistence

All PVCs use the cluster default StorageClass unless `persistence.storageClass` is set.

| Value | Default | Description |
|---|---|---|
| `persistence.storageClass` | `""` | StorageClass for all PVCs. `""` uses the cluster default |
| `persistence.master.size` | `10Gi` | Manager master data volume |
| `persistence.master.accessMode` | `ReadWriteOnce` | |
| `persistence.masterFilebeat.size` | `5Gi` | Manager master Filebeat state volume |
| `persistence.masterFilebeat.accessMode` | `ReadWriteOnce` | |
| `persistence.worker.size` | `20Gi` | Manager worker data volume |
| `persistence.worker.accessMode` | `ReadWriteOnce` | |
| `persistence.workerFilebeat.size` | `5Gi` | Manager worker Filebeat state volume |
| `persistence.workerFilebeat.accessMode` | `ReadWriteOnce` | |
| `persistence.indexer.size` | `50Gi` | Indexer (OpenSearch) data volume |
| `persistence.indexer.accessMode` | `ReadWriteOnce` | |
| `persistence.dashboard.size` | `5Gi` | Dashboard config and assets volume |
| `persistence.dashboard.accessMode` | `ReadWriteOnce` | |

### Resources

| Value | Default | Description |
|---|---|---|
| `resources.manager.requests.cpu` | `200m` | CPU request for master and worker manager pods |
| `resources.manager.requests.memory` | `1024Mi` | Memory request for manager pods |
| `resources.manager.limits.cpu` | `500m` | CPU limit for manager pods |
| `resources.manager.limits.memory` | `2048Mi` | Memory limit for manager pods |
| `resources.indexer.requests.cpu` | `200m` | CPU request for indexer pod |
| `resources.indexer.requests.memory` | `1024Mi` | Memory request for indexer pod |
| `resources.indexer.limits.cpu` | `500m` | CPU limit for indexer pod |
| `resources.indexer.limits.memory` | `2048Mi` | Memory limit for indexer pod |
| `resources.indexer.javaOpts` | `"-Xms1g -Xmx1g"` | JVM heap size for OpenSearch — keep in sync with memory limits |
| `resources.dashboard.requests` | `{}` | CPU/memory requests for dashboard (unset by default) |
| `resources.dashboard.limits` | `{}` | CPU/memory limits for dashboard (unset by default) |

### Filebeat

| Value | Default | Description |
|---|---|---|
| `filebeat.sslVerificationMode` | `full` | SSL verification mode for Filebeat → Indexer connection (`full`, `certificate`, `none`) |

### Dashboard

| Value | Default | Description |
|---|---|---|
| `dashboard.serviceType` | `ClusterIP` | Service type for the dashboard. Use `NodePort` when ingress is disabled and you want direct cluster access |

### Ingress (Traefik)

The Wazuh Dashboard can be exposed publicly via a Traefik Ingress with TLS termination by cert-manager. The internal Wazuh PKI (pod-to-pod) is independent of the ingress certificate.

| Value | Default | Description |
|---|---|---|
| `ingress.enabled` | `false` | Enable the Traefik Ingress for the dashboard |
| `ingress.ingressClassName` | `traefik` | IngressClass to use |
| `ingress.host` | `wazuh.example.com` | Hostname for the dashboard Ingress rule and TLS SAN |
| `ingress.clusterIssuer` | `letsencrypt-prod` | cert-manager `ClusterIssuer` name used to issue the public TLS certificate |
| `ingress.tlsSecretName` | `wazuh-dashboard-ingress-tls` | Name of the Secret cert-manager creates to store the TLS keypair |

### Keycloak

| Value | Default | Description |
|---|---|---|
| `keycloak.enabled` | `false` | Deploy Keycloak and configure the dashboard for OIDC login |
| `keycloak.tag` | `"23.0.6"` | Keycloak image tag |
| `keycloak.realm` | `wazuh` | Keycloak realm name — must match the auto-imported realm JSON |
| `keycloak.clientSecret` | `"CHANGE_ME"` | OIDC client secret shared between Keycloak and the dashboard |
| `keycloak.admin.username` | `admin` | Keycloak master realm admin username |
| `keycloak.admin.password` | `"CHANGE_ME"` | Keycloak master realm admin password |
| `keycloak.db.name` | `keycloak` | PostgreSQL database name |
| `keycloak.db.username` | `keycloak` | PostgreSQL user |
| `keycloak.db.password` | `"CHANGE_ME"` | PostgreSQL password |
| `keycloak.db.storageSize` | `10Gi` | PVC size for the CNPG PostgreSQL cluster |
| `keycloak.resources.requests.cpu` | `200m` | CPU request for the Keycloak pod |
| `keycloak.resources.requests.memory` | `512Mi` | Memory request for the Keycloak pod |
| `keycloak.resources.limits.cpu` | `1000m` | CPU limit for the Keycloak pod |
| `keycloak.resources.limits.memory` | `1Gi` | Memory limit for the Keycloak pod |

---

## Upgrading

```bash
helm upgrade wazuh ./chart --namespace wazuh
```

> **Note:** Changing `clusterIP` on existing services (e.g. the first time `wazuh-cluster` was converted to headless) requires deleting the service first:
> ```bash
> kubectl delete service wazuh-cluster -n wazuh
> helm upgrade wazuh ./chart --namespace wazuh
> ```

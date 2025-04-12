Here's an improved and more readable version of your Markdown document for deploying Wazuh on Kubernetes. I've corrected grammar, clarified instructions, added headers and formatting, and expanded certain parts for better understanding—all while keeping the original structure and intent intact.

---

```markdown
# Wazuh in Kubernetes

This is a working Wazuh deployment tested in Kubernetes. It is currently a **static setup** with many **hardcoded values**, mainly intended for development and testing purposes.

> ⚠️ Production deployment will require modifications for dynamic scaling, secrets management, and persistent storage configurations.

---

## Certificates (SSL/TLS)

All certificates are **pre-generated and hardcoded** to match the Kubernetes services defined in the Wazuh setup. If you need to generate new certificates, you must update the configuration file and rerun the certificate generation container.

### Example Certificate Config (`certs.yml`)

```yaml
nodes:
  # Wazuh Indexer server nodes
  indexer:
    - name: wazuh-indexer.wazuh.svc
      ip: wazuh-indexer.wazuh.svc

  # Wazuh Server nodes
  server:
    - name: wazuh-manager.wazuh.svc
      ip: wazuh-manager.wazuh.svc
      node_type: master  
    - name: wazuh-worker.wazuh.svc
      ip: wazuh-worker.wazuh.svc
      node_type: worker

  # Wazuh Dashboard node
  dashboard:
    - name: wazuh-dashboard.wazuh.svc
      ip: wazuh-dashboard.wazuh.svc
```

### Generate Certificates with Docker Compose

Create a Docker Compose file (e.g., `generate-certs.yaml`):

```yaml
services:
  generator:
    image: wazuh/wazuh-certs-generator:0.0.2
    hostname: wazuh-certs-generator
    volumes:
      - ./config/wazuh_indexer_ssl_certs/:/certificates/
      - ./config/certs.yml:/config/certs.yml
    environment:
      - HTTP_PROXY=wazuh.wazuh.svc
```

Then run:

```bash
docker compose -f generate-certs.yaml run generator
```

### Create Kubernetes Secrets from Generated Certs

For example, to encode the `admin.pem` file:

```bash
cat admin.pem | base64 | tr -d '\n'
```

Copy the result and insert it into your Kubernetes secret manifest.

---

## Access

By default, **no external access is exposed** for the Wazuh Dashboard, API, or other components. You must either:

- Create your own Kubernetes `Service` of type `LoadBalancer` or `NodePort`, **or**
- Use `kubectl port-forward` for local access

### Default Credentials

- **Username:** `admin`
- **Password:** `admin`

> ⚠️ These are the Wazuh defaults unless explicitly changed.

---

## Storage Requirements

Make sure a **default StorageClass** is defined in your cluster. Persistent volumes will be automatically created based on this.

---

## Deployment

1. Clone the Wazuh deployment repository:

```bash
git clone https://github.com/your-org/wazuh-k8s-deployment.git
cd wazuh-k8s-deployment
```

> 🚧 No official release or versioning yet. Use the latest commit on `main`.

2. Deploy using Helm:

```bash
helm upgrade --install wazuh . --namespace wazuh --create-namespace
```

---

## Additional Notes

- This setup does **not yet support autoscaling or horizontal pods**.
- Ideal for isolated environments, POCs, and integration testing.
- Configuration, logging, and scaling will need tuning before moving to production.

---

## Roadmap / To-Do

- [ ] Dynamic secret generation with cert-manager
- [ ] Ingress controller support (NGINX/Traefik)
- [ ] Production-grade Helm chart with values schema
- [ ] CI/CD integration for Wazuh container builds

---

```

Let me know if you'd like a full example Helm values file, Kubernetes secret manifest, or ingress setup next!

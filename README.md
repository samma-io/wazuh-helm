
# Wazuh in Kubernetes

This is a working Wazuh deployment tested in Kubernetes. It is currently a **static setup** with many **hardcoded values**, mainly intended for development and testing purposes.

> ⚠️ Production deployment will require modifications for dynamic scaling, secrets management, and persistent storage configurations.

---


## Req
This deploymedn need to be install in en k8s cluster before this chart

- CertManager


## Certificates (SSL/TLS)
All certificate are setupo using Cert manager and you need to have it install in the cluster for the certs to be installed.
All certs are then setup to the right pod fir usage


## Access

By default, **no external access is exposed** for the Wazuh Dashboard, API, or other components. You must either:

- Create your own Kubernetes `Service` of type `LoadBalancer` or `NodePort`, **or**
- Use `kubectl port-forward` for local access

### Dashbord
The dashboard is exposed using a nodeport and you can access it over https.

https://10.0.0.33:30272/

### Default Credentials

- **Username:** `admin`
- **Password:** `admin`

> ⚠️ These are the Wazuh defaults unless explicitly changed.


### Manager
Manager access is open with a loadbalancer. This is where you will be usingh to connect your clients.




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

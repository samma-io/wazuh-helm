# Wazuh In kubernetes

This is working wazhu deployment testet in kubernetes.
Its a static deployment and alot is hardcoded to get it to work.


## Certs
all the certs are pre added and to match the service that are used. If new certs are need then generate them with the  config.


```
nodes:
  # Wazuh indexer server nodes
  indexer:
    - name: wazuh-indexer.wazuh.svc
      ip: wazuh-indexer.wazuh.svc

  # Wazuh server nodes
  # Use node_type only with more than one Wazuh manager
  server:
    - name: wazuh-manager.wazuh.svc
      ip: wazuh-manager.wazuh.svc
      node_type: master  
    - name: wazuh-worker.wazuh.svc
      ip: wazuh-worker.wazuh.svc
      node_type: worker
  # Wazuh dashboard node
  dashboard:
    - name: wazuh-dashboard.wazuh.svc
      ip: wazuh-dashboard.wazuh.svc
````
Then add the docker-compose.yml file called generate-certs.yaml

```
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

And run the command 

```
docker compose -f generate-certs.yaml run  generator
```

To get the cert into the secrets run 

```
cat admin.pem  | base64 |tr -d '\n'
```

## Access
By default there is no access to the Wazuh deployment. So you need to add your own svc ore portforward the access.

Default login is admin/admin  (I have not set this and made it up is default )

## pre
Disk you need to have a storage ready and set as default storage class.




## Deploy

First clone this repo. We dont make any release as now ...
then install using common helm.

```
helm upgarde --install wazuh . --namespace wazuh --create-namespace
```
#/bin/bash
echo "Set the wazuh on pause"
kubectl patch statefulset wazuh-dashboard  -p '{"spec": {"replicas":1 }}' -n wazuh
kubectl patch statefulset wazuh-indexer  -p '{"spec": {"replicas":1 }}' -n wazuh
kubectl patch statefulset wazuh-manager-master  -p '{"spec": {"replicas":1 }}' -n wazuh
kubectl patch statefulset wazuh-manager-worker-0  -p '{"spec": {"replicas":1 }}' -n wazuh




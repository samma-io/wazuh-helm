{{/*
Standard labels applied to all resources.
*/}}
{{- define "wazuh.labels" -}}
app.kubernetes.io/name: wazuh
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Values.wazuh.tag | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
helm.sh/chart: {{ .Chart.Name }}-{{ .Chart.Version }}
{{- end }}

{{/*
Conditional nodeSelector block. Set .Values.nodeSelector to {} to disable.
Usage: {{- include "wazuh.nodeSelector" . | nindent 6 }}
*/}}
{{- define "wazuh.nodeSelector" -}}
{{- with .Values.nodeSelector }}
nodeSelector:
  {{- toYaml . | nindent 2 }}
{{- end }}
{{- end }}

{{/*
PVC spec block. Pass the per-component persistence map merged with storageClass.
Usage: {{- include "wazuh.pvcSpec" (dict "component" .Values.persistence.master "storageClass" .Values.persistence.storageClass) }}
*/}}
{{- define "wazuh.pvcSpec" -}}
accessModes:
  - {{ .component.accessMode }}
{{- if .storageClass }}
storageClassName: {{ .storageClass }}
{{- end }}
resources:
  requests:
    storage: {{ .component.size }}
{{- end }}

{{/*
"true" in collector mode, empty otherwise. Use with: if (include "wazuh.collector" .)
*/}}
{{- define "wazuh.collector" -}}
{{- if eq .Values.mode "collector" -}}true{{- end -}}
{{- end }}

{{/*
Rejects value combinations the chart cannot render sensibly.
*/}}
{{- define "wazuh.validate" -}}
{{- if not (has .Values.mode (list "default" "collector")) -}}
{{- fail (printf "mode must be 'default' or 'collector', got '%s'" .Values.mode) -}}
{{- end -}}
{{- if include "wazuh.collector" . -}}
{{- if .Values.keycloak.enabled -}}
{{- fail "mode=collector has no dashboard to log into: set keycloak.enabled=false" -}}
{{- end -}}
{{- if .Values.ingress.enabled -}}
{{- fail "mode=collector has no dashboard to route to: set ingress.enabled=false" -}}
{{- end -}}
{{- end -}}
{{- end }}

{{/*
"true" when the Vector sidecar runs, empty otherwise.
*/}}
{{- define "wazuh.collectorVector" -}}
{{- if and (include "wazuh.collector" .) .Values.collector.vector.enabled -}}true{{- end -}}
{{- end }}

{{/*
Vector sidecar container. Pass the root context and the manager's PVC volume name:
  include "wazuh.vectorSidecar" (dict "root" . "dataVolume" "wazuh-worker-master")
Runs as the image's wazuh user (999), the owner of alerts.json (mode 640).
*/}}
{{- define "wazuh.vectorSidecar" -}}
{{- $v := .root.Values.collector.vector -}}
- name: vector
  image: {{ printf "%s:%s" $v.image $v.tag | quote }}
  args: ["--config", "/etc/vector/vector.yaml"]
  env:
    - name: NATS_URL
      value: {{ required "collector.vector.natsUrl is required when the sidecar is enabled" $v.natsUrl | quote }}
    - name: WAZUH_LANE_SUBJECT
      value: {{ $v.subject | quote }}
  ports:
    - name: vector-api
      containerPort: 8686
  livenessProbe:
    httpGet:
      path: /health
      port: vector-api
    periodSeconds: 30
  readinessProbe:
    httpGet:
      path: /health
      port: vector-api
    periodSeconds: 10
  securityContext:
    runAsNonRoot: true
    runAsUser: 999
    runAsGroup: 999
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: true
    capabilities:
      drop: ["ALL"]
  resources:
    {{- toYaml $v.resources | nindent 4 }}
  volumeMounts:
    - name: vector-config
      mountPath: /etc/vector
      readOnly: true
    - name: wazuh-alerts
      mountPath: /wazuh/alerts
      readOnly: true
    # File checkpoints and the disk buffer survive a pod restart.
    - name: {{ .dataVolume }}
      subPath: vector
      mountPath: /var/lib/vector
{{- end }}

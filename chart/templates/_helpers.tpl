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

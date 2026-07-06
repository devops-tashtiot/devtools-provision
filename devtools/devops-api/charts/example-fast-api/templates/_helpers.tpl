{{- define "api.name" -}}
{{- if .Values.releasename -}}
{{- .Values.releasename | trunc 26 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name "api" | trunc 26 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}


{{- define "api.labels" -}}
app: {{ template "api.name" . }}
{{- end }}

{{/*
Create the name of the namespace
*/}}
{{- define "api.namespaceName" -}}
{{- default .Release.Namespace .Values.namespace }}
{{- end }}

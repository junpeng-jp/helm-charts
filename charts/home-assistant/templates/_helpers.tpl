{{- define "home-assistant.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "home-assistant.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{- define "home-assistant.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "home-assistant.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "home-assistant.selectorLabels" -}}
app.kubernetes.io/name: {{ include "home-assistant.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "home-assistant.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "home-assistant.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "home-assistant.image" -}}
{{- $registry := .Values.global.image.registry -}}
{{- $repository := .Values.global.image.repository -}}
{{- $tag := .Values.global.image.tag -}}
{{- if .Values.global.image.digest }}
{{- printf "%s/%s@%s" $registry $repository .Values.global.image.digest }}
{{- else }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- end }}
{{- end }}

{{- define "home-assistant.initContainer.image" -}}
{{- $image := .Values.homeAssistant.initContainer.image -}}
{{- if $image.digest }}
{{- printf "%s/%s@%s" $image.registry $image.repository $image.digest }}
{{- else }}
{{- printf "%s/%s:%s" $image.registry $image.repository $image.tag }}
{{- end }}
{{- end }}

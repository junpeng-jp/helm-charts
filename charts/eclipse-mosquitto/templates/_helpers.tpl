{{- define "eclipse-mosquitto.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "eclipse-mosquitto.fullname" -}}
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

{{- define "eclipse-mosquitto.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "eclipse-mosquitto.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "eclipse-mosquitto.selectorLabels" -}}
app.kubernetes.io/name: {{ include "eclipse-mosquitto.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "eclipse-mosquitto.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "eclipse-mosquitto.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "eclipse-mosquitto.image" -}}
{{- $registry := .Values.global.image.registry -}}
{{- $repository := .Values.global.image.repository -}}
{{- $tag := .Values.global.image.tag -}}
{{- if .Values.global.image.digest }}
{{- printf "%s/%s@%s" $registry $repository .Values.global.image.digest }}
{{- else }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- end }}
{{- end }}

{{- define "eclipse-mosquitto.initContainer.image" -}}
{{- $image := .Values.mosquitto.initContainer.image -}}
{{- if $image.digest }}
{{- printf "%s/%s@%s" $image.registry $image.repository $image.digest }}
{{- else }}
{{- printf "%s/%s:%s" $image.registry $image.repository $image.tag }}
{{- end }}
{{- end }}

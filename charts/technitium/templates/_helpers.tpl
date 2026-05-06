{{- define "technitium.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{- define "technitium.fullname" -}}
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

{{- define "technitium.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{ include "technitium.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "technitium.selectorLabels" -}}
app.kubernetes.io/name: {{ include "technitium.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "technitium.serviceAccountName" -}}
{{- if .Values.serviceAccount.create }}
{{- default (include "technitium.fullname" .) .Values.serviceAccount.name }}
{{- else }}
{{- default "default" .Values.serviceAccount.name }}
{{- end }}
{{- end }}

{{- define "technitium.image" -}}
{{- $registry := .Values.global.imageRegistry | default .Values.image.registry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest }}
{{- printf "%s/%s@%s" $registry $repository .Values.image.digest }}
{{- else }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- end }}
{{- end }}

{{/*
Build env entries from config and networking.service.
Renders a YAML list fragment (no leading "env:" key).
Append env[] after this in the statefulset to allow value overrides.
*/}}
{{- define "technitium.configEnv" -}}
{{- $mainPorts := .Values.networking.service.main.ports -}}
{{- $dnsPorts := .Values.networking.service.dns.ports -}}
- name: DNS_SERVER_DOMAIN
  value: {{ .Values.config.domain | quote }}
{{- if .Values.config.preferIPv6 }}
- name: DNS_SERVER_PREFER_IPV6
  value: "true"
{{- end }}
{{- with .Values.config.recursion.mode }}
- name: DNS_SERVER_RECURSION
  value: {{ . | quote }}
{{- end }}
{{- with .Values.config.recursion.networkACL }}
- name: DNS_SERVER_RECURSION_NETWORK_ACL
  value: {{ . | quote }}
{{- end }}
{{- if .Values.config.blocking.enabled }}
- name: DNS_SERVER_ENABLE_BLOCKING
  value: "true"
{{- end }}
{{- if .Values.config.blocking.allowTxtReport }}
- name: DNS_SERVER_ALLOW_TXT_BLOCKING_REPORT
  value: "true"
{{- end }}
{{- with .Values.config.blocking.blockListUrls }}
- name: DNS_SERVER_BLOCK_LIST_URLS
  value: {{ join ", " . | quote }}
{{- end }}
{{- with .Values.config.forwarders.addresses }}
- name: DNS_SERVER_FORWARDERS
  value: {{ join ", " . | quote }}
- name: DNS_SERVER_FORWARDER_PROTOCOL
  value: {{ $.Values.config.forwarders.protocol | quote }}
{{- end }}
{{- if .Values.config.logging.useLocalTime }}
- name: DNS_SERVER_LOG_USING_LOCAL_TIME
  value: "true"
{{- end }}
{{- with .Values.config.logging.folderPath }}
- name: DNS_SERVER_LOG_FOLDER_PATH
  value: {{ . | quote }}
{{- end }}
{{- if gt (.Values.config.logging.maxLogFileDays | int) 0 }}
- name: DNS_SERVER_LOG_MAX_LOG_FILE_DAYS
  value: {{ .Values.config.logging.maxLogFileDays | quote }}
{{- end }}
{{- if .Values.config.stats.enableInMemoryStats }}
- name: DNS_SERVER_STATS_ENABLE_IN_MEMORY_STATS
  value: "true"
{{- end }}
{{- if gt (.Values.config.stats.maxStatFileDays | int) 0 }}
- name: DNS_SERVER_STATS_MAX_STAT_FILE_DAYS
  value: {{ .Values.config.stats.maxStatFileDays | quote }}
{{- end }}
- name: DNS_SERVER_WEB_SERVICE_HTTP_PORT
  value: {{ (index $mainPorts "http").port | quote }}
{{- $https := index $mainPorts "https" -}}
{{- if and $https (ne (toString $https.enabled) "false") }}
- name: DNS_SERVER_WEB_SERVICE_ENABLE_HTTPS
  value: "true"
- name: DNS_SERVER_WEB_SERVICE_HTTPS_PORT
  value: {{ $https.port | quote }}
{{- if .Values.config.webService.selfSignedCert }}
- name: DNS_SERVER_WEB_SERVICE_USE_SELF_SIGNED_CERT
  value: "true"
{{- end }}
{{- if .Values.config.webService.httpToTlsRedirect }}
- name: DNS_SERVER_WEB_SERVICE_HTTP_TO_TLS_REDIRECT
  value: "true"
{{- end }}
{{- end }}
{{- $dohPlain := index $dnsPorts "doh-plain" -}}
{{- if and $dohPlain (ne (toString $dohPlain.enabled) "false") }}
- name: DNS_SERVER_OPTIONAL_PROTOCOL_DNS_OVER_HTTP
  value: "true"
{{- end }}
{{- end }}

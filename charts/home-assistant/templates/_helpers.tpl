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

{{- define "home-assistant.renderImage" -}}
{{- if .digest }}
{{- printf "%s/%s@%s" .registry .repository .digest }}
{{- else }}
{{- printf "%s/%s:%s" .registry .repository .tag }}
{{- end }}
{{- end }}

{{- define "home-assistant.image" -}}
{{- include "home-assistant.renderImage" .Values.global.image }}
{{- end }}

{{- define "home-assistant.initContainer.image" -}}
{{- include "home-assistant.renderImage" .Values.homeAssistant.initContainer.image }}
{{- end }}

{{- /* Returns "true" or "" (empty string). Use with include in if-predicates: {{- if include "home-assistant.bootstrapEnabled" . }} */ -}}
{{- define "home-assistant.bootstrapEnabled" -}}
{{- if or .Values.homeAssistant.initContainer.tasks.setupHACS.enabled
         .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.enabled -}}
true
{{- end -}}
{{- end -}}

{{- define "home-assistant.testImage" -}}
{{- include "home-assistant.renderImage" .Values.global.testImage }}
{{- end }}

{{- define "home-assistant.initContainers" -}}
{{- if .Values.homeAssistant.gitops.enabled }}
- name: gitops-setup
  image: {{ include "home-assistant.initContainer.image" . }}
  imagePullPolicy: {{ .Values.homeAssistant.initContainer.image.pullPolicy }}
  # Runs as root to write into /config (mounted PVC); s6 is not involved here.
  securityContext:
    runAsUser: 0
    readOnlyRootFilesystem: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: [ALL]
  command:
    - sh
    - -c
    - |
      set -e
      mkdir -p /config/gitops/scripts
      {{- range .Values.homeAssistant.gitops.repos }}
      mkdir -p /config/gitops/{{ .name }}
      printf '%s\n' {{ .url | quote }} > /config/gitops/{{ .name }}/remote
      {{- end }}
  {{- with .Values.homeAssistant.initContainer.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    {{- /* config volume always present: gitops.enabled → persistence.enabled (validated) */}}
    - name: config
      mountPath: /config
{{- end }}
{{- if include "home-assistant.bootstrapEnabled" . }}
- name: bootstrap
  image: {{ include "home-assistant.initContainer.image" . }}
  imagePullPolicy: {{ .Values.homeAssistant.initContainer.image.pullPolicy }}
  # Runs as root; apk install (HACS) requires a writable root filesystem.
  securityContext:
    runAsUser: 0
    readOnlyRootFilesystem: false
    allowPrivilegeEscalation: false
    capabilities:
      drop: [ALL]
  command: [sh, /run/init-scripts/bootstrap.sh]
  env:
    {{- if .Values.homeAssistant.initContainer.tasks.setupHACS.enabled }}
    - name: HACS_ENABLED
      value: "true"
    - name: HACS_VERSION
      value: {{ .Values.homeAssistant.initContainer.tasks.setupHACS.version | quote }}
    {{- if .Values.homeAssistant.initContainer.tasks.setupHACS.sha256 }}
    - name: HACS_SHA256
      value: {{ .Values.homeAssistant.initContainer.tasks.setupHACS.sha256 | quote }}
    {{- end }}
    {{- end }}
    {{- if .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.enabled }}
    - name: SECRETS_ENABLED
      value: "true"
    - name: SECRETS_DIR
      value: "/run/secrets/{{ .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.secretName }}"
    {{- end }}
  {{- with .Values.homeAssistant.initContainer.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: config
      mountPath: /config
    - name: init-scripts
      mountPath: /run/init-scripts
      readOnly: true
    {{- if .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.enabled }}
    - name: {{ .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.secretName }}
      mountPath: /run/secrets/{{ .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.secretName }}
      readOnly: true
    {{- end }}
{{- end }}
{{- with .Values.initContainers }}
{{ toYaml . -}}
{{- end }}
{{- if and .Values.homeAssistant.configuration.enabled .Values.homeAssistant.configuration.checkConfig.enabled }}
- name: check-config
  image: {{ include "home-assistant.image" . }}
  imagePullPolicy: {{ .Values.global.image.pullPolicy }}
  # Runs as root; hass --script check_config writes temporary files under /config.
  securityContext:
    runAsUser: 0
    allowPrivilegeEscalation: false
    readOnlyRootFilesystem: false
    capabilities:
      drop: [ALL]
  command:
    - hass
    - --script
    - check_config
    - --config
    - /config
  {{- with .Values.homeAssistant.configuration.checkConfig.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: config
      mountPath: /config
    - name: ha-configuration
      mountPath: /config/configuration.yaml
      subPath: configuration.yaml
      readOnly: true
{{- end }}
{{- end }}

{{- define "home-assistant.volumes" -}}
{{- if .Values.persistence.existingClaim }}
- name: config
  persistentVolumeClaim:
    claimName: {{ .Values.persistence.existingClaim }}
{{- end }}
{{- if .Values.homeAssistant.configuration.enabled }}
- name: ha-configuration
  configMap:
    name: {{ include "home-assistant.fullname" . }}-configuration
{{- end }}
{{- if include "home-assistant.bootstrapEnabled" . }}
- name: init-scripts
  configMap:
    name: {{ include "home-assistant.fullname" . }}-init-scripts
    defaultMode: 0755
{{- end }}
{{- if .Values.homeAssistant.gitops.enabled }}
- name: gitops-sync-script
  configMap:
    name: {{ include "home-assistant.fullname" . }}-gitops-sync-script
    defaultMode: 0755
- name: gitops-known-hosts
  configMap:
    name: {{ .Values.homeAssistant.gitops.ssh.knownHostsConfigMap }}
- name: gitops-ssh-key
  secret:
    secretName: {{ .Values.homeAssistant.gitops.ssh.keySecret }}
    defaultMode: 0400
- name: gitops-ha-check
  emptyDir:
    medium: Memory
    sizeLimit: {{ .Values.homeAssistant.gitops.gitWorkspaceSizeLimit }}
{{- if .Values.homeAssistant.gitops.ssh.allowedSignersConfigMap }}
- name: gitops-allowed-signers
  configMap:
    name: {{ .Values.homeAssistant.gitops.ssh.allowedSignersConfigMap }}
{{- end }}
{{- end }}
{{- if .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.enabled }}
- name: {{ .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.secretName }}
  secret:
    secretName: {{ .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.secretName }}
{{- end }}
{{- range .Values.secretVolumeMounts }}
- name: {{ .name | default .secretName }}
  secret:
    secretName: {{ .secretName }}
{{- end }}
{{- with .Values.extraVolumes }}
{{ toYaml . -}}
{{- end }}
{{- end }}

{{- /* Emits a YAML list of containerPort entries for all enabled services and ports. */ -}}
{{- define "home-assistant.containerPorts" -}}
{{- range $svcName := keys .Values.networking.service | sortAlpha -}}
{{- $svc := index $.Values.networking.service $svcName -}}
{{- if $svc.enabled -}}
{{- range $portName := keys $svc.ports | sortAlpha -}}
{{- $port := index $svc.ports $portName -}}
{{- if ne $port.enabled false }}
- name: {{ $portName }}
  containerPort: {{ $port.port }}
  protocol: {{ $port.protocol }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{- define "home-assistant.name" -}}
{{- default .Chart.Name .Values.nameOverride }}
{{- end }}

{{- define "home-assistant.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name }}
{{- end }}
{{- end }}
{{- end }}

{{- define "home-assistant.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" }}
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
{{- $ref := printf "%s/%s" .registry .repository | trimPrefix "/" | trimSuffix "/" -}}
{{- if .digest -}}
{{- printf "%s@%s" $ref .digest -}}
{{- else if .tag -}}
{{- printf "%s:%s" $ref .tag -}}
{{- else -}}
{{- $ref -}}
{{- end -}}
{{- end }}

{{- define "home-assistant.image" -}}
{{- include "home-assistant.renderImage" .Values.global.image }}
{{- end }}

{{- define "home-assistant.initContainer.image" -}}
{{- include "home-assistant.renderImage" .Values.homeAssistant.initContainer.image }}
{{- end }}

{{- define "home-assistant.testImage" -}}
{{- include "home-assistant.renderImage" .Values.global.testImage }}
{{- end }}

{{- define "home-assistant.portEnabled" -}}
{{- if eq .enabled true }}true{{- end -}}
{{- end -}}

{{- define "home-assistant.bootstrapEnabled" -}}
{{- $hacsEnabled := .Values.homeAssistant.initContainer.tasks.setupHACS.enabled -}}
{{- $secretsEnabled := .Values.homeAssistant.initContainer.tasks.setupSecretsYaml.enabled -}}
{{- if or $hacsEnabled $secretsEnabled -}}true{{- end -}}
{{- end -}}

{{- define "home-assistant.gitopsEnabled" -}}
{{- if .Values.homeAssistant.initContainer.tasks.gitops.enabled -}}true{{- end -}}
{{- end -}}

{{- define "home-assistant.isGitOpsSSH" -}}
{{- $found := dict -}}
{{- range .Values.homeAssistant.initContainer.tasks.gitops.repos -}}
  {{- if regexMatch `^(git@|ssh://)` (.url | default "") -}}
    {{- $_ := set $found "v" true -}}
  {{- end -}}
{{- end -}}
{{- if $found.v -}}true{{- end -}}
{{- end -}}

{{- define "home-assistant.initContainer.securityContext" -}}
runAsUser: 0
readOnlyRootFilesystem: false
allowPrivilegeEscalation: false
capabilities:
  drop: [ALL]
{{- end -}}

{{- define "home-assistant.initContainer.baseFields" -}}
image: {{ include "home-assistant.initContainer.image" . }}
imagePullPolicy: {{ .Values.homeAssistant.initContainer.image.pullPolicy }}
securityContext:
  {{- include "home-assistant.initContainer.securityContext" . | nindent 2 }}
{{- end -}}

{{- define "home-assistant.configmapName.configuration" -}}
{{- include "home-assistant.fullname" . }}-configuration
{{- end -}}

{{- define "home-assistant.configmapName.initScripts" -}}
{{- include "home-assistant.fullname" . }}-init-scripts
{{- end -}}

{{- define "home-assistant.configmapName.gitops" -}}
{{- include "home-assistant.fullname" . }}-gitops
{{- end -}}

{{- define "home-assistant.gitopsSignersEnabled" -}}
{{- $found := dict -}}
{{- range .Values.homeAssistant.initContainer.tasks.gitops.repos -}}
  {{- if .allowedSigners -}}
    {{- $_ := set $found "v" true -}}
  {{- end -}}
{{- end -}}
{{- if $found.v -}}true{{- end -}}
{{- end -}}

{{- define "home-assistant.configmapName.gitopsSigners" -}}
{{- include "home-assistant.fullname" . }}-gitops-signers
{{- end -}}

{{- define "home-assistant.initContainer.gitopsInit" -}}
{{- if include "home-assistant.gitopsEnabled" . -}}
{{- $gitops := .Values.homeAssistant.initContainer.tasks.gitops -}}
{{- $isGitOpsSSH := include "home-assistant.isGitOpsSSH" . -}}
- name: gitops-init
  {{- include "home-assistant.initContainer.baseFields" . | nindent 2 }}
  command:
    - sh
    - /run/gitops/gitops-setup
  {{- with .Values.homeAssistant.initContainer.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: config
      mountPath: /config
    - name: gitops-configmap
      mountPath: /run/gitops
      readOnly: true
    {{- if $isGitOpsSSH }}
    - name: gitops-ssh-key
      mountPath: /run/secrets/gitops/ssh_key
      subPath: {{ $gitops.ssh.secretKey }}
      readOnly: true
    {{- end }}
    {{- if include "home-assistant.gitopsSignersEnabled" . }}
    - name: gitops-signers-configmap
      mountPath: /run/gitops-signers
      readOnly: true
    {{- end }}
{{- end -}}
{{- end -}}

{{- define "home-assistant.initContainer.bootstrap" -}}
{{- $hacs := .Values.homeAssistant.initContainer.tasks.setupHACS -}}
{{- $secrets := .Values.homeAssistant.initContainer.tasks.setupSecretsYaml -}}
{{- $initScriptsMountPath := "/run/init-scripts" -}}
{{- if include "home-assistant.bootstrapEnabled" . }}
- name: bootstrap
  {{- include "home-assistant.initContainer.baseFields" . | nindent 2 }}
  command:
    - sh
    - {{ $initScriptsMountPath }}/bootstrap.sh
  env:
    - name: HACS_ENABLED
      value: {{ $hacs.enabled | quote }}
    {{- if $hacs.enabled }}
    - name: HACS_VERSION
      value: {{ $hacs.version | quote }}
    {{- if $hacs.sha256 }}
    - name: HACS_SHA256
      value: {{ $hacs.sha256 | quote }}
    {{- end }}
    {{- end }}
    - name: SECRETS_ENABLED
      value: {{ $secrets.enabled | quote }}
    {{- if $secrets.enabled }}
    - name: SECRETS_DIR
      value: "/run/secrets/{{ $secrets.secretName }}"
    {{- end }}
  {{- with .Values.homeAssistant.initContainer.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: config
      mountPath: /config
    - name: init-scripts
      mountPath: {{ $initScriptsMountPath }}
      readOnly: true
    {{- if $secrets.enabled }}
    - name: {{ $secrets.secretName }}
      mountPath: /run/secrets/{{ $secrets.secretName }}
      readOnly: true
    {{- end }}
{{- end -}}
{{- end -}}

{{- define "home-assistant.initContainer.checkConfig" -}}
{{- if and .Values.homeAssistant.configuration.enabled .Values.homeAssistant.configuration.checkConfig.enabled }}
- name: check-config
  image: {{ include "home-assistant.image" . }}
  imagePullPolicy: {{ .Values.global.image.pullPolicy }}
  securityContext:
    {{- include "home-assistant.initContainer.securityContext" . | nindent 4 }}
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
{{- end -}}
{{- end -}}

{{- define "home-assistant.initContainers" -}}
{{- include "home-assistant.initContainer.gitopsInit" . }}
{{- include "home-assistant.initContainer.bootstrap" . }}
{{- with .Values.initContainers }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- include "home-assistant.initContainer.checkConfig" . }}
{{- end -}}

{{- define "home-assistant.volumes" -}}
{{- if .Values.persistence.existingClaim }}
- name: config
  persistentVolumeClaim:
    claimName: {{ .Values.persistence.existingClaim }}
{{- end }}
{{- if .Values.homeAssistant.configuration.enabled }}
- name: ha-configuration
  configMap:
    name: {{ include "home-assistant.configmapName.configuration" . }}
{{- end }}
{{- if include "home-assistant.bootstrapEnabled" . }}
- name: init-scripts
  configMap:
    name: {{ include "home-assistant.configmapName.initScripts" . }}
    defaultMode: 0644
{{- end }}
{{- if include "home-assistant.gitopsEnabled" . }}
{{- $gitops := .Values.homeAssistant.initContainer.tasks.gitops -}}
{{- $isGitOpsSSH := include "home-assistant.isGitOpsSSH" . }}
- name: gitops-configmap
  configMap:
    name: {{ include "home-assistant.configmapName.gitops" . }}
    defaultMode: 0644
{{- if $isGitOpsSSH }}
- name: gitops-ssh-key
  secret:
    secretName: {{ $gitops.ssh.secretName }}
    defaultMode: 0400
{{- end }}
{{- if include "home-assistant.gitopsSignersEnabled" . }}
- name: gitops-signers-configmap
  configMap:
    name: {{ include "home-assistant.configmapName.gitopsSigners" . }}
    defaultMode: 0644
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
{{- toYaml . | nindent 0 }}
{{- end }}
{{- end -}}

{{- define "home-assistant.containerPorts" -}}
{{- range $svcName := keys .Values.networking.service | sortAlpha -}}
{{- $svc := index $.Values.networking.service $svcName -}}
{{- if $svc.enabled -}}
{{- range $portName := keys $svc.ports | sortAlpha -}}
{{- $port := index $svc.ports $portName -}}
{{- if include "home-assistant.portEnabled" $port }}
- name: {{ $portName }}
  containerPort: {{ $port.port }}
  protocol: {{ $port.protocol | default "TCP" }}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end -}}

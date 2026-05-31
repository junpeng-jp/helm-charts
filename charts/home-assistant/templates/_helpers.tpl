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

{{- define "home-assistant.gitops.podSecurityContext" -}}
{{- $ctx := mergeOverwrite (dict "fsGroup" 1000) (.Values.podSecurityContext | default dict) -}}
{{- if .Values.homeAssistant.gitops.enabled -}}
{{- toYaml $ctx -}}
{{- else if not (empty .Values.podSecurityContext) -}}
{{- toYaml .Values.podSecurityContext -}}
{{- end -}}
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
{{- include "home-assistant.initContainer.bootstrap" . }}
{{- with .Values.initContainers }}
{{- toYaml . | nindent 0 }}
{{- end }}
{{- include "home-assistant.initContainer.checkConfig" . }}
{{- end -}}

{{- define "home-assistant.mainContainer.env" -}}
{{- with .Values.env }}
{{- toYaml . }}
{{- end }}
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
{{- if .Values.homeAssistant.gitops.enabled }}
{{- $gitops := .Values.homeAssistant.gitops }}
- name: gitops-runtime
  configMap:
    name: {{ include "home-assistant.configmapName.gitops" . }}
    items:
      - key: config.json
        path: config.json
        mode: 0644
      - key: gitconfig
        path: gitconfig
        mode: 0644
      {{- if $gitops.credentials.ssh.secretName }}
      - key: ssh_config
        path: ssh_config
        mode: 0644
      - key: known_hosts
        path: known_hosts
        mode: 0644
      {{- end }}
      {{- range $gitops.repos }}
      {{- $repo := . }}
      {{- $httpsEntry := dict }}
      {{- range $gitops.credentials.https }}
      {{- if contains .host $repo.url }}
      {{- $httpsEntry = . }}
      {{- end }}
      {{- end }}
      {{- if or $httpsEntry.host $repo.allowedSigners }}
      - key: {{ $repo.name }}.gitconfig
        path: {{ $repo.name }}/gitconfig
        mode: 0644
      {{- end }}
      {{- if $httpsEntry.host }}
      - key: {{ $repo.name }}.credential
        path: {{ $repo.name }}/credential
        mode: 0755
      {{- end }}
      {{- if $repo.allowedSigners }}
      - key: {{ $repo.name }}.allowed-signers
        path: {{ $repo.name }}/allowed-signers
        mode: 0644
      {{- end }}
      {{- end }}
{{- if $gitops.credentials.ssh.secretName }}
- name: gitops-ssh-key
  secret:
    secretName: {{ $gitops.credentials.ssh.secretName }}
    defaultMode: 0440
{{- end }}
{{- range $gitops.credentials.https }}
- name: gitops-https-{{ .host | replace "." "-" }}
  secret:
    secretName: {{ .secretName }}
    defaultMode: 0440
{{- end }}
- name: gitops-workspace
  emptyDir: {}
{{- end }}
{{- end -}}

{{- define "home-assistant.configmapName.gitops" -}}
{{- include "home-assistant.fullname" . }}-gitops
{{- end -}}

{{- define "home-assistant.gitops.image" -}}
{{- include "home-assistant.renderImage" .Values.homeAssistant.gitops.image }}
{{- end -}}

{{- define "home-assistant.gitops.configJson" -}}
{{- $gitops := .Values.homeAssistant.gitops -}}
{{- $repos := list -}}
{{- range $gitops.repos -}}
{{- $repo := dict "name" .name "url" .url "verifyCommit" (default false .verifyCommit) -}}
{{- if .commandQueueSize -}}{{- $_ := set $repo "commandQueueSize" .commandQueueSize -}}{{- end -}}
{{- $repos = append $repos $repo -}}
{{- end -}}
{{- $cfg := dict "runtimeDir" "/run/gitops-runtime" "workDir" "/tmp/gitops" "workspaceDir" "/gitops/repos" "repos" $repos -}}
{{- if $gitops.webhook.haWebhookId -}}
{{- $notification := dict "type" "ha-webhook" "url" (printf "http://localhost:8123/api/webhook/%s" $gitops.webhook.haWebhookId) -}}
{{- if $gitops.webhook.queueSize -}}{{- $_ := set $notification "queueSize" $gitops.webhook.queueSize -}}{{- end -}}
{{- if $gitops.webhook.maxBatchSize -}}{{- $_ := set $notification "maxBatchSize" $gitops.webhook.maxBatchSize -}}{{- end -}}
{{- if $gitops.webhook.batchInterval -}}{{- $_ := set $notification "batchInterval" $gitops.webhook.batchInterval -}}{{- end -}}
{{- $_ := set $cfg "notification" $notification -}}
{{- end -}}
{{- $cfg | toJson -}}
{{- end -}}

{{- define "home-assistant.gitops.gitconfig" -}}
{{- $gitops := .Values.homeAssistant.gitops -}}
{{- range $gitops.repos -}}
{{- $repo := . -}}
{{- $hasHttps := false -}}
{{- range $gitops.credentials.https -}}
{{- if contains .host $repo.url -}}{{- $hasHttps = true -}}{{- end -}}
{{- end -}}
{{- if or $hasHttps $repo.allowedSigners }}
[includeIf "hasconfig:remote.*.url:{{ $repo.url }}"]
  path = /run/gitops-runtime/{{ $repo.name }}/gitconfig
{{ end -}}
{{- end -}}
{{- end -}}

{{- define "home-assistant.gitops.repoGitconfig" -}}
{{- $repo := .repo -}}
{{- $gitops := .gitops -}}
{{- range $gitops.credentials.https -}}
{{- if contains .host $repo.url -}}
[credential "https://{{ .host }}"]
  helper = /run/gitops-runtime/{{ $repo.name }}/credential
{{ end -}}
{{- end -}}
{{- if $repo.allowedSigners -}}
[gpg]
  format = ssh
[gpg "ssh"]
  allowedSignersFile = /run/gitops-runtime/{{ $repo.name }}/allowed-signers
{{- end -}}
{{- end -}}

{{- define "home-assistant.gitops.credentialHelper" -}}
{{- $secretKey := default "token" .cred.secretKey -}}
#!/bin/sh
[ "$1" = get ] || exit 0
printf 'username=%s\npassword=%s\n' '{{ .cred.login | default "x-access-token" }}' "$(cat /run/secrets/gitops-https/{{ .cred.host }}/{{ $secretKey }})"
{{- end -}}

{{- define "home-assistant.gitops.sshConfig" -}}
{{- $gitops := .Values.homeAssistant.gitops -}}
Host *
  IdentityFile /run/secrets/gitops-ssh-key/{{ $gitops.credentials.ssh.secretKey }}
  UserKnownHostsFile /run/gitops-runtime/known_hosts
  StrictHostKeyChecking yes
  IdentitiesOnly yes
  StrictModes no
{{- end -}}

{{- define "home-assistant.sidecar.gitops" -}}
{{- $gitops := .Values.homeAssistant.gitops -}}
- name: gitops
  image: {{ include "home-assistant.gitops.image" . }}
  imagePullPolicy: {{ $gitops.image.pullPolicy }}
  securityContext:
    runAsUser: 1000
    runAsGroup: 1000
    runAsNonRoot: true
    allowPrivilegeEscalation: false
    capabilities:
      drop: [ALL]
  ports:
    - name: gitops
      containerPort: {{ $gitops.port }}
      protocol: TCP
  env:
    - name: GITOPS_PORT
      value: {{ $gitops.port | quote }}
    - name: GITOPS_CONFIG_FILE
      value: /run/gitops-runtime/config.json
  {{- with .Values.homeAssistant.gitops.resources }}
  resources:
    {{- toYaml . | nindent 4 }}
  {{- end }}
  volumeMounts:
    - name: gitops-runtime
      mountPath: /run/gitops-runtime
      readOnly: true
    - name: gitops-workspace
      mountPath: /gitops/repos
    {{- if $gitops.credentials.ssh.secretName }}
    - name: gitops-ssh-key
      mountPath: /run/secrets/gitops-ssh-key
      readOnly: true
    {{- end }}
    {{- range $gitops.credentials.https }}
    {{- $secretKey := default "token" .secretKey }}
    - name: gitops-https-{{ .host | replace "." "-" }}
      mountPath: /run/secrets/gitops-https/{{ .host }}/{{ $secretKey }}
      subPath: {{ $secretKey }}
      readOnly: true
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

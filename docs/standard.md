# Helm chart design standards

Charts that don't share conventions diverge quickly — making them hard to read, deploy, and maintain. These rules keep every chart in this repo consistent, secure, and familiar to anyone who opens a `values.yaml` for the first time.

# Chart design rules

**Consistency across charts:** Every chart exposes the same baseline fields in the same order. A reader opening any chart's `values.yaml` should find the structure immediately familiar.

**No inline secrets:** Never put secret values in `values.yaml`. Inject secrets by referencing an externally-managed Kubernetes Secret via `env[].valueFrom.secretKeyRef` or `secretVolumeMounts`.

**Logical separation of concerns:** Cluster configurations logically based on how the application works in the real world. For example, keep container registries swappable to support air-gapped installations. Separate container security from pod security to allow elevated permissions in init containers.

**Flexibility via specification passthrough:** Special configurations (e.g. `extraVolumes`, `extraVolumeMounts`, `initContainers`, `pod.affinity`, etc.) let chart users pass through exact Kubernetes specs for rendering.

---

## Order fields in values.yaml

Maintain this top-to-bottom ordering in `values.yaml` for consistency across charts:

0. [`global`](#0-global) - includes `global.image`
1. [`nameOverride`, `fullnameOverride`, `replicaCount`](#1-naming)
2. [`serviceAccount`](#2-service-accounts)
3. [`initContainers`, `env`, `secretVolumeMounts`, `extraVolumes`, `extraVolumeMounts`, `startupProbe`, `livenessProbe`, `readinessProbe`, `resources`](#3-initialization)
4. [`podSecurityContext`, `containerSecurityContext`, `pod`](#4-security-context)
5. [`networking`](#5-networking)
6. [`ingress`](#6-ingress)
7. [`persistence`](#7-storage)
8. [`monitor`](#8-monitors)
9. [Chart-specific subsystems](#9-chart-specific-subsystems)

---

## Validate with values.schema.json

Ship a `values.schema.json` at the chart root. Helm validates user-supplied values against this schema before rendering, surfacing typos and type errors early.

Minimum requirements:

- Set `"$schema": "https://json-schema.org/draft-07/schema#"` and `"type": "object"`.
- Define all top-level keys that appear in `values.yaml`.
- Use `"additionalProperties": false` at the top level to catch unknown keys.
- Mark required fields (those with no meaningful default that must be set by the chart user) in the `"required"` array.
- Validate string formats where practical (e.g. `"enum"` for `pullPolicy`, `"pattern"` for image tags).

Example skeleton:

```json
{
  "$schema": "https://json-schema.org/draft-07/schema#",
  "type": "object",
  "additionalProperties": false,
  "properties": {
    "global": {
      "type": "object",
      "additionalProperties": false,
      "properties": {
        "image": {
          "type": "object",
          "additionalProperties": false,
          "properties": {
            "registry":    { "type": "string" },
            "repository":  { "type": "string" },
            "tag":         { "type": "string" },
            "digest":      { "type": "string" },
            "pullPolicy":  { "type": "string", "enum": ["Always", "IfNotPresent", "Never"] },
            "pullSecrets": { "type": "array", "items": { "type": "string" } }
          }
        }
      }
    },
    "nameOverride": { "type": "string" },
    "fullnameOverride": { "type": "string" }
  }
}
```

---

## 0. Global

`global` holds settings resolved before any chart-specific defaults apply. `global.image` centralises image coordinates for the chart.

```yaml
global:
  image:
    registry: docker.io
    repository: some-org/some-container
    tag: ""                   # required: pin the version to deploy - does not fall back to Chart.AppVersion
    digest: ""                # takes precedence over tag when set (e.g. sha256:abc123)
    pullPolicy: IfNotPresent
    pullSecrets: []           # list of imagePullSecret names
```

Leave `tag` empty in the standard pattern to force the deployer to pin a version explicitly. Charts with a known-good default may pre-fill it (e.g. `tag: "1.2.3"`).

Template rendering pattern in `_helpers.tpl`:

```
{{- define "<chart>.image" -}}
{{- $registry := .Values.global.image.registry -}}
{{- $repository := .Values.global.image.repository -}}
{{- $tag := .Values.global.image.tag -}}
{{- if .Values.global.image.digest }}
{{- printf "%s/%s@%s" $registry $repository .Values.global.image.digest }}
{{- else }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- end }}
{{- end }}
```

---

## 1. Naming

Every chart exposes these fields at the top of `values.yaml`.

```yaml
nameOverride: ""       # replaces the chart-name portion of generated resource names
fullnameOverride: ""   # replaces the entire generated name (release-name + chart-name)

replicaCount: 1        # number of pod replicas; keep at 1 for StatefulSets unless shared storage supports it
```

`_helpers.tpl` handles naming via the standard `<chart>.fullname` pattern. These fields exist in `values.yaml` only to document that the knobs are available.

---

## 2. Service accounts

Every chart includes this block. When `create: false` and `name: ""`, the pod uses the namespace default service account.

```yaml
serviceAccount:
  create: false
  name: ""
  annotations: {}
```

When `create: true`, `_helpers.tpl` creates the ServiceAccount and the pod spec references it. When `create: false` and `name` is non-empty, the pod references a pre-existing service account.

---

## 3. Initialization

Configure how the workload starts and runs: init containers, environment and secret injection, probes, and resource constraints.

### 3.1 Use init containers

Use `initContainers` to pass through full Kubernetes init container specs for direct rendering.

Example — fix volume ownership before the main container starts:

```yaml
initContainers:
  - name: fix-permissions
    image: busybox:1.36
    command: ["sh", "-c", "chown -R 1000:1000 /data"]
    volumeMounts:
      - name: data
        mountPath: /data
    securityContext:
      runAsUser: 0   # root required to chown; main container runs as 1000
```

### 3.2 Inject environment variables

Use the standard Kubernetes `env` list. It supports literal values and references to external Secrets or ConfigMaps. Never put inline secret values in `values.yaml`.

```yaml
env:
  - name: TZ
    value: UTC
  - name: MY_TOKEN
    valueFrom:
      secretKeyRef:
        name: my-external-secret   # must be externally managed (ESO, SOPS, Vault, etc.)
        key: token
  - name: LOG_LEVEL
    valueFrom:
      configMapKeyRef:
        name: my-config
        key: log-level
```

### 3.3 Mount secret files

Use `secretVolumeMounts` to mount a Kubernetes Secret as files. The chart automatically creates the volume and volumeMount. Secrets mount read-only under `/run/secrets/<secretName>/`, which is typically tmpfs-backed on Linux so secret data never touches disk.

```yaml
secretVolumeMounts:
  - secretName: my-external-secret   # K8s Secret name
  - secretName: my-external-secret   # same secret, different mount path
    mountPath: /run/secrets/alias
    name: my-secret-alias            # required: volume names must be unique; set when the same secretName appears more than once
```

The optional `name` field overrides the Kubernetes volume name (defaults to `secretName`). Set it whenever the same `secretName` appears more than once — duplicate volume names cause a Kubernetes admission rejection.

The chart generates:

```yaml
# volumes:
#   - name: my-external-secret
#     secret:
#       secretName: my-external-secret
# volumeMounts:
#   - name: my-external-secret
#     mountPath: /run/secrets/my-external-secret
#     readOnly: true
```

### 3.4 Add extra volumes

Both fields accept full Kubernetes volume and volumeMount specs without wrapping.

```yaml
extraVolumes:
  - name: app-config
    configMap:
      name: my-configmap
  - name: usb-device
    hostPath:
      path: /dev/serial/by-id/usb-...

extraVolumeMounts:
  - name: app-config
    mountPath: /etc/app/config.yaml
    subPath: config.yaml
  - name: usb-device
    mountPath: /dev/ttyUSB0
```

### 3.5 Never use inline secrets

No chart may include a plain-text secret field in `values.yaml` (e.g., `password: ""`). Use `secretKeyRef` in `env` ([Inject environment variables](#32-inject-environment-variables)) or `secretVolumeMounts` ([Mount secret files](#33-mount-secret-files)) to reference an externally-managed Kubernetes Secret instead.

### 3.6 Configure health probes

Include startup, liveness, and readiness probes **only when the app exposes a known HTTP health endpoint**. Each probe has an `enabled` flag.

`startupProbe` is optional. Use it for apps with slow or variable startup times to prevent liveness/readiness probes from firing too early. Default it to `enabled: false`.

```yaml
startupProbe:
  enabled: false
  httpGet:
    path: /
    port: http
  periodSeconds: 10
  failureThreshold: 18
livenessProbe:
  enabled: true
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 60
  periodSeconds: 30
  failureThreshold: 5
readinessProbe:
  enabled: true
  httpGet:
    path: /
    port: http
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
```

When the app has no usable HTTP health endpoint, omit all probe fields entirely and add a one-line comment in the workload template (e.g. `# No HTTP health endpoint - probes omitted`).

Template rendering pattern:

```
{{- if .Values.startupProbe.enabled }}
startupProbe:
  {{- omit .Values.startupProbe "enabled" | toYaml | nindent 2 }}
{{- end }}
{{- if .Values.livenessProbe.enabled }}
livenessProbe:
  {{- omit .Values.livenessProbe "enabled" | toYaml | nindent 2 }}
{{- end }}
```

### 3.7 Set resource limits

Always provide default `requests` and `limits`. You may omit CPU limits intentionally for workloads that spike; document the reason in a comment.

```yaml
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 1Gi
    # cpu intentionally omitted - automation workloads can spike briefly
```

---

## 4. Security context

Follow Bitnami convention: `podSecurityContext` for the shared pod environment, `containerSecurityContext` for the main container's OS-level privileges. Group pod scheduling metadata separately under `pod`. Init containers override security context with their own inline `securityContext` in the `initContainers` spec.

**Charts that require root:** Some applications must run as root (e.g. they manage host devices, raw sockets, or perform privileged system operations). For these charts, omit both `podSecurityContext` and `containerSecurityContext` from `values.yaml` and add a comment in the workload template explaining why (e.g. `# Security context omitted - home-assistant requires root to access host devices`). Don't include empty or permissive security context blocks as placeholders.

### 4.1 Set the pod security context

`podSecurityContext` sets defaults inherited by **all containers** in the pod (init and main). It governs volume ownership, supplemental groups, and kernel-level settings.

```yaml
podSecurityContext:
  fsGroup: 1000               # GID that owns mounted volumes
  supplementalGroups: [20]    # additional GIDs added to all containers (e.g. dialout for serial access)
  sysctls: []                 # kernel parameters scoped to the pod's network namespace
  runAsUser: 1000             # default UID for all containers; overridable per container
  runAsGroup: 1000            # default GID for all containers; overridable per container
  runAsNonRoot: true          # default for all containers; overridable per container
```

`sysctls` accepts a list of `name`/`value` pairs. Only *safe* sysctls (those in Kubernetes' allowlist) are permitted by default. Unsafe sysctls require an explicit `allowedUnsafeSysctls` admission configuration on the node.

```yaml
# Increase the local port range - useful for apps that open many outbound connections
podSecurityContext:
  sysctls:
    - name: net.ipv4.ip_local_port_range
      value: "1024 65535"

# Raise the socket receive/send buffer limits - useful for high-throughput UDP (e.g. DNS, game servers)
podSecurityContext:
  sysctls:
    - name: net.core.rmem_max
      value: "134217728"
    - name: net.core.wmem_max
      value: "134217728"

# Enable TCP fast open for both client and server paths
podSecurityContext:
  sysctls:
    - name: net.ipv4.tcp_fastopen
      value: "3"
```

### 4.2 Set the container security context

`containerSecurityContext` controls what the **main container's process is allowed to do at the OS level** — Linux capabilities, privilege escalation, filesystem mutability, and privileged mode. These settings apply only to the main container and override any pod-level defaults.

```yaml
containerSecurityContext:
  runAsUser: 1000
  runAsGroup: 1000
  runAsNonRoot: true
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  privileged: false
  capabilities:
    drop: [ALL]
    # add: [NET_BIND_SERVICE]   # add back only what the app requires
```

### 4.3 Control pod scheduling

`pod` groups scheduling metadata: fields that control where and how the pod is placed on the cluster. Every field accepts the full Kubernetes spec without wrapping.

```yaml
pod:
  annotations: {}
  nodeSelector: {}
  tolerations: []
  affinity: {}
  hostNetwork: false  # enable only for pods that need to share the host network namespace (e.g. mDNS)
```

Example — pin to a specific node, tolerate a dedicated taint, and label the pod for a backup tool:

```yaml
pod:
  annotations:
    backup.velero.io/backup-volumes: data
  nodeSelector:
    kubernetes.io/hostname: node-01
  tolerations:
    - key: dedicated
      operator: Equal
      value: iot
      effect: NoSchedule
  affinity: {}
```

---

## 5. Networking

`networking.service` is a **map** where each key is a logical service name (e.g. `main`, `dns`). Each entry configures one Kubernetes Service resource. Enable multiple services simultaneously when an application needs to expose different port groups with different service types (e.g. a ClusterIP for HTTP traffic and a LoadBalancer for DNS).

`type` accepts standard Kubernetes service types: `ClusterIP`, `LoadBalancer`, or `NodePort`.

`ports` is a **map** keyed by port name within each service. Each entry specifies `port` and `protocol`. An optional `enabled: false` flag excludes the port from the rendered Service and container spec. Use this for ports that are off by default but meaningful to expose at the user's discretion.

**Keep port names unique across all services within a chart.** The chart derives container ports from all enabled services and their enabled ports. Duplicate names produce an invalid pod spec.

Each chart's `values.schema.json` must define `networking.service` as an object with `"required": ["<name1>", "<name2>"]` and an `additionalProperties` schema describing the per-service shape.

```yaml
networking:
  service:
    webapp:
      enabled: true
      type: ClusterIP
      ports:
        http:
          port: 8080
          protocol: TCP
```

`service.yaml` iterates over all entries and renders one Service per enabled entry. Use `keys | sortAlpha` for deterministic rendering order (map iteration order is non-deterministic in Go and can produce diff noise across helm runs).

Each chart designates one service name as the **primary** service. Use whatever name fits the application (e.g. `app`, `http`, `web`). Document the chosen primary name in a comment above the naming logic.

Template rendering pattern:

```
{{- /* service.yaml */ -}}
{{- /* Primary service name for this chart: "app" (rendered without suffix) */ -}}
{{- range $svcName := keys .Values.networking.service | sortAlpha }}
{{- $svc := index $.Values.networking.service $svcName }}
{{- if $svc.enabled }}
---
apiVersion: v1
kind: Service
metadata:
  name: {{ if eq $svcName "app" }}{{ include "<chart>.fullname" $ }}{{ else }}{{ printf "%s-%s" (include "<chart>.fullname" $) $svcName }}{{ end }}
  ...
spec:
  type: {{ $svc.type }}
  ports:
    {{- range $portName := keys $svc.ports | sortAlpha }}
    {{- $port := index $svc.ports $portName }}
    {{- if (default true $port.enabled) }}
    - name: {{ $portName }}
      port: {{ $port.port }}
      targetPort: {{ $portName }}
      protocol: {{ $port.protocol }}
    {{- end }}
    {{- end }}
{{- end }}
{{- end }}
```

The port `enabled` field uses `default true $port.enabled`. Omitting the field is equivalent to `enabled: true`. Don't use `ne (toString $port.enabled) "false"` — that pattern is fragile and renders ports when `enabled` is `0` or an empty string.

Apply the same range pattern in the workload template to keep container port names in sync:

```
{{- /* statefulset.yaml / deployment.yaml */ -}}
ports:
  {{- range $svcName := keys .Values.networking.service | sortAlpha }}
  {{- $svc := index $.Values.networking.service $svcName }}
  {{- if $svc.enabled }}
  {{- range $portName := keys $svc.ports | sortAlpha }}
  {{- $port := index $svc.ports $portName }}
  {{- if (default true $port.enabled) }}
  - name: {{ $portName }}
    containerPort: {{ $port.port }}
    protocol: {{ $port.protocol }}
  {{- end }}
  {{- end }}
  {{- end }}
  {{- end }}
```

### 5.1 Model multi-protocol ports

Some applications expose the same logical service over multiple transport protocols (e.g., a DNS server listening on both UDP and TCP on port 53). Model each physical port as a separate map entry, and group them with a shared comment. Use multiple named services to group ports by access pattern (e.g. in-cluster HTTP vs. externally-accessible DNS):

```yaml
networking:
  service:
    main:
      enabled: true
      type: ClusterIP
      ports:
        http:
          port: 5380
          protocol: TCP
    dns:
      enabled: false
      type: LoadBalancer
      ports:
        # DNS - UDP and TCP share the same port number; enable both together
        dns-udp:
          port: 53
          protocol: UDP
        dns-tcp:
          port: 53
          protocol: TCP
        # DNS over TLS
        dot:
          port: 853
          protocol: TCP
          enabled: false
```

Kubernetes permits two Service port entries with the same `port` number when their `protocol` values differ.

---

## 6. Ingress

`ingress` configures how the application is exposed outside the cluster.

Multiple ingress mechanisms may be defined in a chart, but **at most one may be enabled at a time**. Enforce this with a template-level `fail` guard at the top of each ingress template (simpler and more readable than JSON Schema `not`/`oneOf` constructs):

```
{{- if and .Values.ingress.gateway.enabled .Values.ingress.traefik.enabled }}
{{- fail "Only one ingress mechanism may be enabled at a time (ingress.gateway or ingress.traefik)" }}
{{- end }}
```

Each ingress template must also guard against the specific service it routes to, since ingress routes require a service.

```
{{- if not .Values.networking.service.<primary>.enabled }}
{{- fail "ingress requires networking.service.<primary> to be enabled" }}
{{- end }}
```

```yaml
ingress:
  gateway:
    enabled: false
    parentRefs:                  # references to Gateway resources that should serve this route
      - name: my-gateway
        namespace: default       # omit if Gateway is in the same namespace as the chart
    hostnames:                   # list of hostnames this route matches (Gateway API HTTPRoute spec)
      - app.example.com

  traefik:
    enabled: false
    entryPoints:
      - websecure
    hostnames:
      - app.example.com
    middlewares: []              # list of Traefik Middleware refs: {name, namespace?}
    # Example: [{name: my-auth}, {name: my-auth, namespace: traefik}]
    tls:
      enabled: false
      secretName: ""        # use a pre-existing TLS secret
      certResolver: ""      # use a Traefik cert resolver (e.g. letsencrypt); ignored when secretName is set
```

`middlewares` entries are objects with `name` (required) and `namespace` (optional; omit for same-namespace middlewares). Template rendering pattern:

```
{{- range .Values.ingress.traefik.middlewares }}
- name: {{ .name }}
  {{- if .namespace }}
  namespace: {{ .namespace }}
  {{- end }}
{{- end }}
```

`httproute.yaml` renders the `gateway.networking.k8s.io/v1` HTTPRoute from `ingress.gateway`. `ingressroute.yaml` renders the `traefik.io/v1alpha1` IngressRoute from `ingress.traefik`. Both route to the `http` port of the primary Service.

---

## 7. Storage

Use the Bitnami-style schema with `enabled` flag and `accessModes` as a list.

```yaml
persistence:
  enabled: true
  storageClass: ""        # "" uses the cluster default
  accessModes:
    - ReadWriteOnce
  size: 5Gi
  annotations: {}
  labels: {}
  existingClaim: ""       # mount an existing PVC instead of creating one; mutually exclusive with existingVolume
  existingVolume: ""      # (StatefulSet only) bind the VolumeClaimTemplate to a specific PV by name. Mutually exclusive with existingClaim
```

When `existingClaim` is non-empty, the chart skips the `volumeClaimTemplates` entry (for StatefulSets) or PVC manifest (for Deployments) and references the named claim directly.

When `existingVolume` is non-empty (StatefulSet charts only), the `volumeClaimTemplates` entry sets `volumeName` to bind the claim to a specific pre-provisioned PV. This is mutually exclusive with `existingClaim`. Enforce this with a template-level `fail` guard:

```
{{- if and .Values.persistence.existingClaim .Values.persistence.existingVolume }}
{{- fail "persistence.existingClaim and persistence.existingVolume are mutually exclusive; set at most one" }}
{{- end }}
```

When rendering labels on a VolumeClaimTemplate, combine standard chart labels with user-supplied `persistence.labels` using Sprig `merge` to avoid duplicate YAML keys. Standard labels win on conflicts:

```
labels:
  {{- merge (include "<chart>.labels" . | fromYaml) (.Values.persistence.labels | default dict) | toYaml | nindent 10 }}
```

Don't emit the two label blocks separately with `toYaml`. Concatenating them produces duplicate keys when any key overlaps, which is technically invalid YAML (last-wins, silently).

---

## 8. Monitors

`monitor.metric` creates a Prometheus `ServiceMonitor` targeting the chart's Service. Disabled by default. Enable it only when the app exposes a Prometheus-compatible scrape endpoint. `labels` must match the target Prometheus instance's `serviceMonitorSelector`.

```yaml
monitor:
  metric:
    enabled: false
    path: /metrics
    port: http
    interval: 30s
    scrapeTimeout: 10s
    labels: {}              # matched against Prometheus serviceMonitorSelector
```

---

## 9. Chart-specific subsystems

Anything that doesn't fit the standard sections goes here, after `monitor`. Each subsystem gets its own top-level key with a comment explaining its purpose.

Name application config keys after the application in camelCase (e.g. `technitium`). This makes clear the block belongs to the app, not the chart harness.

### Rules

- Include an `enabled` flag for any subsystem that is optional.
- Add a comment block above the key explaining when and why a user would configure it.
- Register every chart-specific key in `values.schema.json` with `additionalProperties: false`.

### Examples

```yaml
my-custom-app:
  # config explicitly mounted somewhere
  config:
    key1: value1
  # usb devices required by this app
  usbDevices: []
  # templates mounted for some default setup
  templates: []

```

# Helm Chart Design Standards

# Chart Design Rules

These principles govern the chart design.

**Consistency across Charts:** Every chart exposes the same baseline fields in the same order. A reader opening any chart's `values.yaml` should be quickly familiar with the chart's basic shared setup.

**No inline secrets:** Charts are designed so that secret values never appear in `values.yaml`. Secrets are injected by referencing an externally-managed Kubernetes Secret via `env[].valueFrom.secretKeyRef` or `secretVolumeMounts`.

**Logical Separation of Concerns:** Configurations should be clustered logically based on chart applications in the real world. For example, container registries should be swappable to support air-gapped installations. Container security should be separate from Pod security to allow for elevated permissions in init containers.

**Flexibility via Specification Passthrough:** Special configurations (e.g. `extraVolumes`, `extraVolumeMounts`, `initContainers`, `pod.affinity`, etc.) provides flexibility by allowing chart users to pass through exact kubernetes specs for rendering.

---

## values.yaml Field Order

Maintain this top-to-bottom ordering in `values.yaml` for consistency across charts:

1. [`nameOverride`, `fullnameOverride`](#1-naming)
2. [`image`](#2-image-registry)
3. [`serviceAccount`](#3-service-account)
4. [`initContainers`, `env`, `secretVolumeMounts`, `extraVolumes`, `extraVolumeMounts`, `livenessProbe`, `readinessProbe`, `resources`](#4-initialization)
5. [`podSecurityContext`, `containerSecurityContext`, `pod`](#5-security-context)
6. [`networking`](#6-networking)
7. [`persistence`](#7-storage)
8. [`monitor`](#8-monitors)
9. Chart-specific subsystems (e.g. `usbDevice`)

---

## values.schema.json Schema Validation

Every chart must ship a `values.schema.json` at the chart root. Helm validates user-supplied values against this schema before rendering, surfacing typos and type errors early.

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
    "nameOverride": { "type": "string" },
    "fullnameOverride": { "type": "string" },
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
}
```

---

## 1. Naming

Every chart exposes these two fields at the top of `values.yaml`. They have no effect when empty.

```yaml
nameOverride: ""       # replaces the chart-name portion of generated resource names
fullnameOverride: ""   # replaces the entire generated name (release-name + chart-name)
```

`_helpers.tpl` already handles both via the standard `<chart>.fullname` pattern. The fields exist in `values.yaml` solely to document that the knobs are available.

---

## 2. Image Registry

Split registry from repository. This allows the registry to be changed independently (e.g. to a internal mirror) without touching the repository path.

```yaml
image:
  registry: ghcr.io
  repository: some-org/some-container   # path only — does not include the registry
  tag: ""           # defaults to .Chart.AppVersion when empty
  digest: ""        # takes precedence over tag when set (e.g. sha256:abc123)
  pullPolicy: IfNotPresent
  pullSecrets: []   # list of imagePullSecret names
```

Template rendering pattern in `_helpers.tpl`:

```
{{- define "<chart>.image" -}}
{{- $registry := .Values.image.registry -}}
{{- $repository := .Values.image.repository -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if .Values.image.digest }}
{{- printf "%s/%s@%s" $registry $repository .Values.image.digest }}
{{- else }}
{{- printf "%s/%s:%s" $registry $repository $tag }}
{{- end }}
{{- end }}
```

---

## 3. Service Account

Every chart includes this block. When `create: false` and `name: ""`, the pod uses the namespace default service account.

```yaml
serviceAccount:
  create: false
  name: ""
  annotations: {}
```

When `create: true`, `_helpers.tpl` creates the ServiceAccount and the pod spec references it. When `create: false` and `name` is non-empty, the pod references a pre-existing service account.

---

## 4. Initialization

This section groups everything that configures how the workload starts and runs: init containers, environment and secret injection, probes, and resource constraints.

### 4.1 Init Containers

For any initialization container, initContainers provide a way to passthrough configuration for direct rendering.

Example - fix volume ownership before the main container starts:

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

### 4.2 Environment Variables

Use the standard Kubernetes `env` list. Supports literal values and references to external Secrets or ConfigMaps. No inline secret values are permitted in `values.yaml`.

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

### 4.3 Secret File Mounts

Use `secretVolumeMounts` to mount a Kubernetes Secret as files. The chart automatically creates the volume and volumeMount. Secrets are always mounted under `/run/secrets/<secretName>/` and are always read-only. This path is typically tmpfs-backed on Linux, so secret data does not touch disk.

```yaml
secretVolumeMounts:
  - secretName: my-external-secret   # K8s Secret name
```

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

### 4.4 Extra Volumes

Both fields accept the full Kubernetes volume and volumeMount specs without wrapping.

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

### 4.5 Security Rule

This section enforces the **No inline secrets** design guideline. No chart may include a plain-text secret field in `values.yaml` (e.g., `password: ""`). Use `secretKeyRef` in `env` ([Environment Variables](#42-environment-variables)) or `secretVolumeMounts` ([Secret File Mounts](#43-secret-file-mounts)) to reference an externally-managed Kubernetes Secret instead.

### 4.6 Probes

Liveness and readiness probes sit at the top level of `values.yaml`. Include them **only when the app exposes a known HTTP health endpoint**. Each probe has an `enabled` flag.

```yaml
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

When the app has no usable HTTP health endpoint, omit both fields entirely and add a one-line comment in the workload template (e.g. `# No HTTP health endpoint — probes omitted`).

Template rendering pattern:

```
{{- if .Values.livenessProbe.enabled }}
livenessProbe:
  {{- omit .Values.livenessProbe "enabled" | toYaml | nindent 2 }}
{{- end }}
```

### 4.7 Resources

Always provide default `requests` and `limits`. CPU limits may be omitted intentionally for workloads that spike; document the reason in a comment.

```yaml
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 1Gi
    # cpu intentionally omitted — automation workloads can spike briefly
```

---

## 5. Security Context

Following Bitnami convention, security context is split into two top-level fields: `podSecurityContext` for the shared pod environment and `containerSecurityContext` for the main container's OS-level privileges. Pod scheduling metadata is grouped separately under `pod`. Init containers override security context via their own inline `securityContext` field in the `initContainers` spec.

### 5.1 Pod Security Context

`podSecurityContext` sets defaults inherited by **all containers** in the pod (init and main). It governs the shared pod environment: volume ownership, supplemental groups, and kernel-level settings.

```yaml
podSecurityContext:
  fsGroup: 1000               # GID that owns mounted volumes
  supplementalGroups: [20]    # additional GIDs added to all containers (e.g. dialout for serial access)
  sysctls: []                 # kernel parameters scoped to the pod's network namespace
  runAsUser: 1000             # default UID for all containers; overridable per container
  runAsGroup: 1000            # default GID for all containers; overridable per container
  runAsNonRoot: true          # default for all containers; overridable per container
```

### 5.2 Container Security Context

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

### 5.3 Pod Scheduling

`pod` groups scheduling metadata — fields that control where and how the pod is placed on the cluster. Every field accepts the full Kubernetes spec without wrapping.

```yaml
pod:
  annotations: {}
  nodeSelector: {}
  tolerations: []
  affinity: {}
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

## 6. Networking

Use `networking` to expose the application. `networking.service` configures the Kubernetes Service; `networking.ingress` and `networking.traefikIngress` expose it externally. Enable at most one ingress mechanism per chart instance; enabling both is valid only when routing to different paths or entrypoints.

```yaml
networking:
  service:
    type: ClusterIP
    port: 8080

  ingress:
    enabled: false
    className: nginx
    annotations: {}
    host: app.example.com
    tls:
      enabled: false
      secretName: app-tls

  traefikIngress:
    enabled: false
    entryPoints:
      - websecure
    host: app.example.com
    middlewares: []         # list of Middleware resource names (must exist in same namespace)
    tls:
      enabled: false
      secretName: ""        # use a pre-existing TLS secret
      certResolver: ""      # use a Traefik cert resolver (e.g. letsencrypt); ignored when secretName is set
```

Templates: `service.yaml` renders the Service; `ingress.yaml` renders the `networking.k8s.io/v1` Ingress; `ingressroute.yaml` renders the `traefik.io/v1alpha1` IngressRoute.

### 6.1 Multi-port services

`networking.service.port` is always the primary HTTP port — the one that ingress and ingressroute route to. It is named `http` in both the Service and the container spec so that ingress backends can reference it by name.

When the app exposes additional protocol ports (e.g., a DNS server with UDP/TCP/DoT/DoH), place those ports in a chart-specific values block (section 9) rather than inside `networking`. The service template then renders the primary `http` port from `networking.service.port` followed by the chart-specific ports:

```yaml
# values.yaml — chart-specific section (section 9)
dnsPorts:
  dns: 53       # DNS over UDP and TCP
  dot: 853      # DNS over TLS
  doh: 8053     # DNS over HTTPS (plain HTTP upstream)
  https: 53443  # DNS over HTTPS (TLS)
```

```yaml
# service.yaml
ports:
  - name: http
    port: {{ .Values.networking.service.port }}
    targetPort: http
    protocol: TCP
  - name: dns-udp
    port: {{ .Values.dnsPorts.dns }}
    targetPort: dns-udp
    protocol: UDP
  - name: dns-tcp
    port: {{ .Values.dnsPorts.dns }}
    targetPort: dns-tcp
    protocol: TCP
  - name: dns-dot
    port: {{ .Values.dnsPorts.dot }}
    targetPort: dns-dot
    protocol: TCP
```

Mirror the same named ports in the workload's `containers[].ports` so that `targetPort` resolution works correctly. Kubernetes allows two entries with the same port number when they differ by protocol (e.g., `dns-udp` and `dns-tcp` both on port 53).

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
  existingClaim: ""       # when set, skips PVC creation and uses this claim
```

When `existingClaim` is non-empty, the chart skips the `volumeClaimTemplates` entry (for StatefulSets) or PVC manifest (for Deployments) and references the named claim directly.

---

## 8. Monitors

`monitor.metric` creates a Prometheus `ServiceMonitor` targeting the chart's Service. Disabled by default; enable only when the app exposes a Prometheus-compatible scrape endpoint. `labels` must match the target Prometheus instance's `serviceMonitorSelector`.

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

Anything that doesn't fit the standard sections goes here, after `monitor`, with a comment explaining the purpose. Each subsystem has its own top-level key.

Common patterns:

**Protocol ports** — when a service exposes multiple non-HTTP ports (DNS, MQTT, etc.), collect them under a named key so users can remap them without touching the primary networking block:

```yaml
# DNS protocol ports — Technitium-specific.
dnsPorts:
  dns: 53         # DNS over UDP and TCP
  dot: 853        # DNS over TLS
  doh: 8053       # DNS over HTTPS (plain HTTP upstream)
  https: 53443    # DNS over HTTPS (TLS)
```

**Device passthrough** — for hardware devices mounted from the host:

```yaml
# USB serial device passthrough.
# Always reference the stable by-id path, never /dev/ttyUSBn.
usbDevice:
  enabled: false
  hostPath: /dev/serial/by-id/usb-...
  mountPath: /dev/ttyUSB0
```

Add a `values.schema.json` entry for every chart-specific key using `additionalProperties: false` to keep the schema strict.

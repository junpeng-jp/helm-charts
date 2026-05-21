# Helm chart design standards

Every chart in this repo follows the same structure. A reader opening any `values.yaml` should find it immediately familiar.

## Field ordering in values.yaml

```
0. global                 — image registry and pull settings
1. nameOverride, fullnameOverride, replicaCount
2. serviceAccount
3. initContainers, env, secretVolumeMounts, extraVolumes, extraVolumeMounts,
   startupProbe, livenessProbe, readinessProbe, resources
4. podSecurityContext, containerSecurityContext, pod
5. networking
6. ingress
7. persistence
8. monitor
9. chart-specific subsystems
```

---

## Schema validation

Ship `values.schema.json`. Requirements:

- `"$schema": "https://json-schema.org/draft-07/schema#"`, `"type": "object"`
- Define every top-level key from `values.yaml`
- `"additionalProperties": false` at the top level
- `"required"` for fields with no meaningful default
- `"enum"` for `pullPolicy`; `"pattern"` for tags where practical

### Use `empty` not `not` for maps and lists

`not` is `true` for nil but `false` for `{}` and `[]`. `empty` is `true` for all three.

```
{{- /* Bad — passes for config: {} */ -}}
{{- if and .Values.feature.enabled (not .Values.feature.config) }}

{{- /* Good */ -}}
{{- if and .Values.feature.enabled (empty .Values.feature.config) }}
```

### Validate sibling features symmetrically

When two features share the same shape, apply the same validation to both. Checking one and silently accepting the other creates an inconsistent failure surface.

```
{{- /* Bad — gateway hostnames silently accept [] */ -}}
{{- if and .Values.ingress.traefik.enabled (empty .Values.ingress.traefik.hostnames) }}
{{- fail "traefik.hostnames must have at least one entry" }}
{{- end }}

{{- /* Good */ -}}
{{- if and .Values.ingress.traefik.enabled (empty .Values.ingress.traefik.hostnames) }}
{{- fail "traefik.hostnames must have at least one entry" }}
{{- end }}
{{- if and .Values.ingress.gateway.enabled (empty .Values.ingress.gateway.hostnames) }}
{{- fail "gateway.hostnames must have at least one entry" }}
{{- end }}
```

---

## 0. Global

```yaml
global:
  image:
    registry: docker.io
    repository: some-org/some-container
    tag: ""                   # pin the version; does not fall back to Chart.AppVersion
    digest: ""                # takes precedence over tag when set (e.g. sha256:abc123)
    pullPolicy: IfNotPresent
    pullSecrets: []
```

`_helpers.tpl` rendering pattern — digest takes precedence over tag:

```
{{- define "<chart>.image" -}}
{{- if .Values.global.image.digest }}
{{- printf "%s/%s@%s" .Values.global.image.registry .Values.global.image.repository .Values.global.image.digest }}
{{- else }}
{{- printf "%s/%s:%s" .Values.global.image.registry .Values.global.image.repository .Values.global.image.tag }}
{{- end }}
{{- end }}
```

---

## 1. Naming

```yaml
nameOverride: ""
fullnameOverride: ""
replicaCount: 1
```

---

## 2. Service accounts

```yaml
serviceAccount:
  create: false
  name: ""       # non-empty + create: false → references a pre-existing ServiceAccount
  annotations: {}
```

---

## 3. Initialization

### Init containers, env, and secret injection

`initContainers` passes through full Kubernetes init container specs. Never put secret values in `values.yaml` — reference them via `env[].valueFrom.secretKeyRef` or `secretVolumeMounts`.

`env` accepts the standard Kubernetes list: literal values, `secretKeyRef`, or `configMapKeyRef`.

`secretVolumeMounts` mounts a Kubernetes Secret as read-only files under `/run/secrets/<mountPath>/`. The chart generates the volume and volumeMount.

```yaml
secretVolumeMounts:
  - secretName: my-secret                # → /run/secrets/my-secret/
  - secretName: my-secret
    mountPath: my-secret-alt             # → /run/secrets/my-secret-alt/
    name: my-secret-alt                  # required when the same secretName appears more than once
```

Duplicate volume names cause a Kubernetes admission rejection. Set `name` to disambiguate.

`extraVolumes` and `extraVolumeMounts` pass through full Kubernetes specs unchanged.

### Health probes

Include probes only when the app exposes a known HTTP health endpoint. When it doesn't, omit all probe fields and add a one-line comment in the workload template.

```yaml
startupProbe:
  enabled: false        # use for slow-starting apps to prevent liveness fires during cold start
  httpGet:
    path: /
    port: http
  periodSeconds: 10
  failureThreshold: 18
livenessProbe:
  enabled: true
  httpGet: { path: /, port: http }
  initialDelaySeconds: 60
  periodSeconds: 30
  failureThreshold: 5
readinessProbe:
  enabled: true
  httpGet: { path: /, port: http }
  initialDelaySeconds: 30
  periodSeconds: 10
  failureThreshold: 3
```

Template pattern — use `omit` to strip the `enabled` key before rendering:

```
{{- if .Values.startupProbe.enabled }}
startupProbe:
  {{- omit .Values.startupProbe "enabled" | toYaml | nindent 2 }}
{{- end }}
```

### Resource limits

Always set `requests` and `limits`. You may omit CPU limits for workloads that spike; document the reason.

```yaml
resources:
  requests:
    memory: 256Mi
    cpu: 100m
  limits:
    memory: 1Gi
    # cpu intentionally omitted — workload can spike briefly
```

---

## 4. Security context

Follow Bitnami convention: `podSecurityContext` for shared pod settings, `containerSecurityContext` for main-container OS-level privileges, `pod` for scheduling metadata.

**Charts that require root:** Omit both security context fields and add a comment in the workload template explaining why. Don't include empty or permissive placeholders.

### Pod security context

Inherited by all containers. Governs volume ownership, supplemental groups, and kernel parameters.

```yaml
podSecurityContext:
  fsGroup: 1000
  supplementalGroups: [20]   # additional GIDs; e.g. dialout (20) for serial port access
  sysctls: []                # safe sysctls only; unsafe require allowedUnsafeSysctls on the node
  runAsUser: 1000
  runAsGroup: 1000
  runAsNonRoot: true
```

### Container security context

Applies to the main container only. Overrides pod-level defaults.

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
    # add: [NET_BIND_SERVICE]
```

### Pod scheduling

```yaml
pod:
  annotations: {}
  nodeSelector: {}
  tolerations: []
  affinity: {}
  hostNetwork: false   # enable only when the pod needs the host network namespace (e.g. mDNS)
```

---

## 5. Networking

`networking.service` is a map of logical service names to Kubernetes Service configurations. Each entry renders one Service. Use `keys | sortAlpha` for deterministic iteration order.

Port names must be unique across all services — the chart derives container ports from them. An optional `enabled: false` per port excludes it from the Service and container spec.

```yaml
networking:
  service:
    app:
      enabled: true
      type: ClusterIP
      ports:
        http:
          port: 8080
          protocol: TCP
```

One service name is the **primary** service. Name it `app`, `http`, or whatever fits the application. Document the choice in a comment above the naming logic. The primary service renders without a name suffix; others get `<fullname>-<svcName>`.

### Port-enabled predicate

The `enabled` field is tri-state: absent = enabled, `true` = enabled, `false` = disabled. Use `not (eq $port.enabled false)` in `service.yaml`, the workload template, and `validations.yaml`. All three must use the **exact same predicate** — a mismatch lets misconfigured values pass validation while producing a broken resource at runtime.

> **Warning:** Don't use `(default true $port.enabled)`. Sprig's `default` treats the boolean `false` as empty and returns `true`, so `enabled: false` is silently ignored and the port renders anyway.

```
{{- /* Bad — default true false → true; enabled: false has no effect */ -}}
{{- if (default true $port.enabled) }}

{{- /* Good — false only when enabled is explicitly false; absent (nil) and true both pass */ -}}
{{- if not (eq $port.enabled false) }}
```

Template patterns:

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
spec:
  type: {{ $svc.type }}
  ports:
    {{- range $portName := keys $svc.ports | sortAlpha }}
    {{- $port := index $svc.ports $portName }}
    {{- if not (eq $port.enabled false) }}
    - name: {{ $portName }}
      port: {{ $port.port }}
      targetPort: {{ $portName }}
      protocol: {{ $port.protocol }}
    {{- end }}
    {{- end }}
{{- end }}
{{- end }}
```

```
{{- /* statefulset.yaml / deployment.yaml */ -}}
{{- range $svcName := keys .Values.networking.service | sortAlpha }}
{{- $svc := index $.Values.networking.service $svcName }}
{{- if $svc.enabled }}
{{- range $portName := keys $svc.ports | sortAlpha }}
{{- $port := index $svc.ports $portName }}
{{- if not (eq $port.enabled false) }}
- name: {{ $portName }}
  containerPort: {{ $port.port }}
  protocol: {{ $port.protocol }}
{{- end }}
{{- end }}
{{- end }}
{{- end }}
```

### Headless service `targetPort`

StatefulSet charts must render a headless Service. Include `targetPort` on every port entry — Kubernetes doesn't enforce it for headless services, but omitting it creates an inconsistency with the primary Service.

### Multi-protocol ports

Model each physical port as a separate map entry. Two entries may share the same `port` number when `protocol` differs.

```yaml
dns:
  enabled: false
  type: LoadBalancer
  ports:
    dns-udp:  { port: 53,  protocol: UDP }
    dns-tcp:  { port: 53,  protocol: TCP }
    dot:      { port: 853, protocol: TCP, enabled: false }
```

---

## 6. Ingress

At most one ingress mechanism may be enabled at a time. Enforce this and the service dependency with `fail` guards in `validations.yaml`:

```
{{- if and .Values.ingress.gateway.enabled .Values.ingress.traefik.enabled }}
{{- fail "Only one ingress mechanism may be enabled at a time" }}
{{- end }}
{{- if and .Values.ingress.gateway.enabled (not .Values.networking.service.app.enabled) }}
{{- fail "ingress.gateway requires networking.service.app to be enabled" }}
{{- end }}
```

```yaml
ingress:
  gateway:
    enabled: false
    parentRefs:
      - name: my-gateway
        namespace: default
    hostnames:
      - app.example.com

  traefik:
    enabled: false
    entryPoints:
      - websecure
    hostnames:
      - app.example.com
    middlewares: []           # [{name: my-auth}, {name: my-auth, namespace: traefik}]
    tls:
      enabled: false
      secretName: ""          # pre-existing TLS secret
      certResolver: ""        # Traefik cert resolver; ignored when secretName is set
```

`httproute.yaml` renders the Gateway API HTTPRoute; `ingressroute.yaml` renders the Traefik IngressRoute. Both route to the `http` port of the primary service.

### Keep resource and workload predicates in sync

When a feature flag controls both a supporting resource (ConfigMap, Secret) and a workload volume reference, both templates must use **the exact same guard condition**. Put non-empty field requirements in `validations.yaml` — don't duplicate them in individual resource templates.

```
{{- /* Bad — extra condition in the ConfigMap that the StatefulSet doesn't check */ -}}
{{- if and .Values.gitops.enabled .Values.gitops.knownHosts }}   ← ConfigMap
{{- if .Values.gitops.enabled }}                                  ← StatefulSet volume

{{- /* Good — identical guard in both; validations.yaml enforces the non-empty requirement */ -}}
{{- if .Values.gitops.enabled }}   ← ConfigMap and StatefulSet volume, same condition
```

---

## 7. Storage

```yaml
persistence:
  enabled: true
  storageClass: ""        # "" uses the cluster default
  accessModes:
    - ReadWriteOnce
  size: 5Gi
  annotations: {}
  labels: {}
  existingClaim: ""       # mount an existing PVC; mutually exclusive with existingVolume
  existingVolume: ""      # (StatefulSet only) bind the VolumeClaimTemplate to a named PV
```

`existingClaim` skips the VolumeClaimTemplate and references the named PVC directly. `existingVolume` sets `volumeName` in the VolumeClaimTemplate. Enforce mutual exclusion:

```
{{- if and .Values.persistence.existingClaim .Values.persistence.existingVolume }}
{{- fail "persistence.existingClaim and persistence.existingVolume are mutually exclusive" }}
{{- end }}
```

> **Warning:** When `existingVolume` is set and `storageClass` is empty, emit `storageClassName: ""` in the VolumeClaimTemplate. Omitting it lets the cluster default StorageClass trigger dynamic provisioning instead of binding the named PV.

```
{{- /* Bad — dynamic provisioner creates a new PV instead of binding the named one */ -}}
{{- if .Values.persistence.storageClass }}
storageClassName: {{ .Values.persistence.storageClass }}
{{- end }}

{{- /* Good */ -}}
{{- if .Values.persistence.storageClass }}
storageClassName: {{ .Values.persistence.storageClass }}
{{- else if .Values.persistence.existingVolume }}
storageClassName: ""
{{- end }}
{{- if .Values.persistence.existingVolume }}
volumeName: {{ .Values.persistence.existingVolume }}
{{- end }}
```

Merge chart labels with user-supplied `persistence.labels` using Sprig `merge`. Chart labels win on conflicts. Don't emit two separate `toYaml` blocks — duplicate keys are silently invalid YAML.

```
{{- /* Good — chart labels win; user labels fill in the rest */ -}}
labels:
  {{- merge (include "<chart>.labels" . | fromYaml) (.Values.persistence.labels | default dict) | toYaml | nindent 10 }}

{{- /* Bad — duplicate keys when a user label shares a name with a chart label */ -}}
labels:
  {{- include "<chart>.labels" . | nindent 10 }}
  {{- toYaml .Values.persistence.labels | nindent 10 }}

{{- /* Bad — user labels silently override chart labels, breaking Helm tracking */ -}}
labels:
  {{- merge .Values.persistence.labels (include "<chart>.labels" . | fromYaml) | toYaml | nindent 10 }}
```

---

## 8. Monitors

```yaml
monitor:
  metric:
    enabled: false
    path: /metrics
    port: http            # must match a port name in an enabled service
    interval: 30s
    scrapeTimeout: 10s
    labels: {}            # must match the Prometheus serviceMonitorSelector
```

---

## 9. Chart-specific subsystems

Place chart-specific configuration after `monitor`, keyed by the application name in camelCase (e.g. `technitium`).

- Include `enabled` for any optional subsystem.
- Add a comment block explaining when and why a user would configure it.
- Register every key in `values.schema.json` with `additionalProperties: false`.

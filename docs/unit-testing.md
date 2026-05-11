# Write chart unit tests

Unit tests use [helm-unittest](https://github.com/helm-unittest/helm-unittest). Tests live in `charts/<chart>/tests/`.

---

## Group tests by configuration domain

Organise test files by configuration domain, not by template. A single behavioral concern (e.g. persistence) often touches one template, but grouping by domain keeps related edge cases together and makes the suite easier to navigate.

```
tests/
  standard_test.yaml          # minimal happy path + full happy path across all resources
  ingress_test.yaml           # all ingress mechanisms (gateway + traefik) in one place
  monitor_test.yaml           # ServiceMonitor guard + scrape config
  persistence_test.yaml       # VolumeClaimTemplate, existingClaim, existingVolume
  init_containers_test.yaml   # task ordering, images, destructive-consequence mounts
  configuration_test.yaml     # config / packages / themes ConfigMap seeding
  networking_test.yaml        # Service naming, disabled service, port rendering
  secrets_test.yaml           # secretVolumeMounts path and name override behavior
  validations_test.yaml       # all validation guard tests
  fixtures/
    minimal-values.yaml       # minimum viable install with all optionals disabled
    full-values.yaml          # all optional features enabled at once
```

Name test files after the domain they cover (`persistence_test.yaml`, `ingress_test.yaml`). Set the `suite` label to match (`Persistence`, `Ingress`).

When a file tests mutually exclusive templates (e.g. `httproute.yaml` and `ingressroute.yaml`), list both in the suite-level `templates:` block. Since only one renders at a time, the document index stays unambiguous per test.

---

## Know what to test

Write two categories of tests per configuration group.

1. **Golden path** — one test that renders a realistic, representative values configuration and asserts the most important structural fields. This is your regression anchor.
2. **Targeted edge cases** — one test per meaningful branch in the template logic.

Aim for 3-4 tests per configuration group.

**Test these edge cases:**
- Chart-specific branching logic (e.g. `hostNetwork` flipping `dnsPolicy`, digest taking precedence over tag, `existingClaim` vs a generated `VolumeClaimTemplate`).
- Behavior with destructive consequences if wrong (wrong PVC strategy, missing security context, dropped volume mount).
- Guard tests for optional resources: one test confirming the resource is **not** rendered when disabled. The enabled case is covered by the golden path.

**Don't test these:**
- Mirror tests: if "enabled renders" is covered, "disabled empty" is usually obvious unless the disabled path has a non-trivial side effect.
- Standard Helm conditionals: `if eq .Values.foo ""` omitting a field is Helm behavior, not chart logic.
- Structural checks in isolation: `name: RELEASE-NAME-chart` or `replicas: 1` belong inside the golden-path test, not as standalone tests.
- Exhaustive permutations: two or three representative inputs are enough.

---

## Structure a test file

Each file covers exactly one template.

```yaml
suite: StatefulSet                    # human label shown in test output
templates:
  - templates/statefulset.yaml        # path relative to the chart root
tests:
  - it: renders a StatefulSet with realistic defaults
    set:                              # inline value overrides (key: value)
      image.tag: "1.2.3"
    values:                           # fixture files to merge in (relative to tests/)
      - fixtures/default-values.yaml
    asserts:
      - isKind:
          of: StatefulSet
      - equal:
          path: spec.template.spec.containers[0].image
          value: docker.io/org/app:1.2.3
```

You can combine `set` and `values` in the same test. `set` keys override anything loaded by `values`.

---

## Use assertions

| Assertion | What it checks | Example |
|-----------|----------------|---------|
| `isKind` | resource Kind | `isKind: {of: StatefulSet}` |
| `equal` | exact value at a path | `equal: {path: spec.type, value: LoadBalancer}` |
| `notExists` | path is absent | `notExists: {path: spec.volumeClaimTemplates}` |
| `contains` | array contains an object | `contains: {path: spec.ports, content: {name: http}}` |
| `hasDocuments` | number of rendered docs | `hasDocuments: {count: 0}` |
| `matchRegex` | string matches pattern | `matchRegex: {path: metadata.name, pattern: ^my-}` |

Use `hasDocuments: {count: 0}` for disabled-guard tests. It confirms the template renders nothing without needing to assert on an absent path.

Paths use dot-notation with bracket indexing: `spec.template.spec.containers[0].image`.
Map keys with dots or slashes must be quoted: `spec.selector["app.kubernetes.io/name"]`.

---

## Use fixtures

Put reusable values blocks in `tests/fixtures/`. Load them with the `values` key.

```yaml
tests:
  - it: renders with production-like config
    values:
      - fixtures/default-values.yaml   # path relative to tests/
    asserts:
      - isKind:
          of: StatefulSet
```

Use `values` when the same block is shared across multiple tests or test files. Inline `set` is fine for single-use overrides.

A fixture file is a plain `values.yaml` fragment. Only include the keys relevant to the tests that use it.

```yaml
# tests/fixtures/default-values.yaml
image:
  tag: "1.2.3"
persistence:
  storageClass: local-path
```

---

## Examples

### Guard test (disabled resource)

```yaml
suite: Ingress (nginx)
templates:
  - templates/ingress.yaml
tests:
  - it: does not render when ingress is disabled
    set:
      networking.ingress.enabled: false
    asserts:
      - hasDocuments:
          count: 0

  - it: renders with host routing and TLS when enabled
    set:
      networking.ingress.enabled: true
      networking.ingress.host: app.example.com
      networking.ingress.tls.enabled: true
      networking.ingress.tls.secretName: app-tls
    asserts:
      - isKind:
          of: Ingress
      - equal:
          path: spec.rules[0].host
          value: app.example.com
      - equal:
          path: spec.tls[0].secretName
          value: app-tls
      - equal:
          path: spec.rules[0].http.paths[0].backend.service.port.name
          value: http
```

### Branching logic (digest over tag)

```yaml
  - it: uses digest over tag when both are set
    set:
      image.tag: "1.0.0"
      image.digest: "sha256:abc123"
    asserts:
      - equal:
          path: spec.template.spec.containers[0].image
          value: docker.io/org/app@sha256:abc123
```

### Persistence branching (existingClaim vs VolumeClaimTemplate)

```yaml
  - it: mounts existing PVC instead of creating a VolumeClaimTemplate
    set:
      persistence.existingClaim: my-pvc
    asserts:
      - notExists:
          path: spec.volumeClaimTemplates
      - contains:
          path: spec.template.spec.volumes
          content:
            name: config
            persistentVolumeClaim:
              claimName: my-pvc

  - it: sets storageClassName in VolumeClaimTemplate when specified
    set:
      persistence.storageClass: local-path
    asserts:
      - equal:
          path: spec.volumeClaimTemplates[0].spec.storageClassName
          value: local-path
```

### Multi-port service

When a chart uses chart-specific port values (section 9 of the standard), assert against the ports array by index.

```yaml
suite: Service
templates:
  - templates/service.yaml
tests:
  - it: renders all DNS and dashboard ports
    asserts:
      - equal:
          path: spec.ports[0].name
          value: http
      - equal:
          path: spec.ports[0].port
          value: 5380
      - equal:
          path: spec.ports[1].name
          value: dns-udp
      - equal:
          path: spec.ports[1].port
          value: 53
      - equal:
          path: spec.ports[1].protocol
          value: UDP
```

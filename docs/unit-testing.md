# Chart Unit Testing Guide

Unit tests use [helm-unittest](https://github.com/helm-unittest/helm-unittest). Tests live in `charts/<chart>/tests/`.

---

## Philosophy

Two categories of tests per template:

1. **Golden path** — one test that renders a realistic, representative values configuration and asserts the most important structural fields. This is the regression anchor.
2. **Targeted edge cases** — one test per meaningful branch in the template logic.

Aim for **3–5 tests per template**.

---

## Test file anatomy

Each file covers exactly one template. The top-level structure:

```yaml
suite: StatefulSet                    # human label shown in test output
templates:
  - templates/statefulset.yaml        # path relative to the chart root
tests:
  - it: renders a StatefulSet with realistic defaults   # test description
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

`set` and `values` can be combined in the same test. `set` keys override anything loaded by `values`.

---

## What to test

**Golden path**
- Render with values that resemble a real deployment (use a fixture file if the config is reused across tests).
- Assert kind, name, and the 3–4 fields most likely to break silently (image ref, port, selector labels, key mounts).

**Edge cases — test these**
- Chart-specific branching logic (e.g. `hostNetwork` flipping `dnsPolicy`, digest taking precedence over tag, `existingClaim` vs a generated `VolumeClaimTemplate`).
- Behavior with destructive consequences if wrong (wrong PVC strategy, missing security context, dropped volume mount).
- Guard tests for optional resources: one test confirming the resource is **not** rendered when disabled. (The enabled case is covered by the golden path.)

---

## What not to test

- **Mirror tests**: if "enabled → renders" is covered, "disabled → empty" is usually obvious and does not need its own test — unless the disabled path has a non-trivial side effect.
- **Standard Helm conditionals**: `if eq .Values.foo ""` omitting a field is Helm behavior, not chart logic.
- **Structural checks in isolation**: `name: RELEASE-NAME-chart` or `replicas: 1` belong inside the golden-path test, not as standalone tests.
- **Exhaustive permutations**: two or three representative inputs are enough; do not enumerate every possible value.

---

## Assertions reference

| Assertion | What it checks | Example |
|-----------|----------------|---------|
| `isKind` | resource Kind | `isKind: {of: StatefulSet}` |
| `equal` | exact value at a path | `equal: {path: spec.type, value: LoadBalancer}` |
| `notExists` | path is absent | `notExists: {path: spec.volumeClaimTemplates}` |
| `contains` | array contains an object | `contains: {path: spec.ports, content: {name: http}}` |
| `hasDocuments` | number of rendered docs | `hasDocuments: {count: 0}` |
| `matchRegex` | string matches pattern | `matchRegex: {path: metadata.name, pattern: ^my-}` |

Use `hasDocuments: {count: 0}` for disabled-guard tests — it confirms the template renders nothing without needing to assert on an absent path.

Paths use dot-notation with bracket indexing: `spec.template.spec.containers[0].image`.  
Map keys with dots or slashes must be quoted: `spec.selector["app.kubernetes.io/name"]`.

---

## Fixtures

Put reusable values blocks in `tests/fixtures/`. Load them with the `values` key:

```yaml
tests:
  - it: renders with production-like config
    values:
      - fixtures/default-values.yaml   # path relative to tests/
    asserts:
      - isKind:
          of: StatefulSet
```

Use `values` when the same values block is shared across multiple tests or multiple test files. Inline `set` is fine for single-use overrides.

A fixture file is a plain `values.yaml` fragment — only include the keys relevant to the tests that use it:

```yaml
# tests/fixtures/default-values.yaml
image:
  tag: "1.2.3"
persistence:
  storageClass: local-path
```

---

## Complete examples

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

### Branching logic test (digest over tag)

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

When a chart uses chart-specific port values (section 9 of the standard), assert against the ports array by index:

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

---

## File structure

```
tests/
  statefulset_test.yaml     # golden path + persistence/security/digest edge cases
  service_test.yaml         # golden path only — or multi-port assertions
  ingress_test.yaml         # disabled guard + TLS branch
  ingressroute_test.yaml    # disabled guard + TLS / certResolver branch
  servicemonitor_test.yaml  # disabled guard + scrape config
  fixtures/
    default-values.yaml     # realistic base config reused across test files
```

Name test files `<template-name>_test.yaml`. The `suite` label should match the resource kind or template purpose (`StatefulSet`, `Ingress (nginx)`, `ServiceMonitor`).

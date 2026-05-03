# Chart Testing with kind

Integration tests use [chart-testing](https://github.com/helm/chart-testing) (`ct`) and [kind](https://kind.sigs.k8s.io/) to install each chart into a real testing cluster and confirm the pod is healthy.

---

## Philosophy

**Integration tests should validate runtime behaviour and not template output**

Integration tests should deploy the rendered manifests into a real testing Kubernetes cluster and confirm the application actually runs. The testing cluster should have sufficient isolation from the real cluster, and can be bootstrapped at the start of a test, and torn down after test completion.

**One `ci/` values file per deployment scenario**

Each `*-values.yaml` file should define a meaningful deployment scenario, and will each trigger a `ct` install.

- `basic-setup-values.yaml` covers the standard deployment of the chart.
- Add a second file only when there is a meaningfully different **runtime** configuration to validate (e.g. a HA deployment, or swapping out local storage for a more sophisticated setup, etc.).

**Helm test pods for connectivity checks**

`test-connection.yaml` confirms that the Service endpoint is reachable after the workload becomes healthy. Using `wget --spider` is sufficient to make sure that everything is reachable.

Charts without an HTTP health endpoint can omit `templates/tests/` entirely.

---

## Configurations

### `ct.yaml`

```yaml
# ct.yaml
chart-dirs:
  - charts
target-branch: main
helm-extra-args: "--timeout 5m"
```

### `kind-config.yaml`

Single control-plane node. No workers needed for these single-app charts.

```yaml
# kind-config.yaml
kind: Cluster
apiVersion: kind.x-k8s.io/v1alpha4
nodes:
  - role: control-plane
```

---

## Chart setup

`ct` discovers all files matching `*-values.yaml` in `ci/` and runs a bootstraps a cluster using the helm values.

### `ci/basic-setup-values.yaml`

The basic setup cover fields that are required by `values.schema.json` or that the app needs to start (e.g. a required env var referencing an existing Secret).

```yaml
# charts/<chart>/ci/basic-setup-values.yaml
image:
  tag: "<current appVersion>"   # pin to avoid pulling latest unexpectedly

persistence:
  enabled: true
  storageClass: local-path
  size: 1Gi
```

### `templates/tests/test-connection.yaml`

A single test pod that confirms the app is reachable via `wget --spider`.

```yaml
# charts/<chart>/templates/tests/test-connection.yaml
apiVersion: v1
kind: Pod
metadata:
  name: {{ include "<chart>.fullname" . }}-test-connection
  labels:
    {{- include "<chart>.labels" . | nindent 4 }}
  annotations:
    "helm.sh/hook": test
spec:
  restartPolicy: Never
  containers:
    - name: wget
      image: busybox
      command:
        - wget
        - --spider
        - -q
        - http://{{ include "<chart>.fullname" . }}:{{ .Values.networking.service.port }}/
```

Replace `<chart>` with the actual chart name in the `include` calls (e.g. `home-assistant`).

---

## Local Chart Testing

Two tasks are provided in devbox to execute chart testing locally. See `scripts/ct-test.sh` for more details.

```bash
# Test all charts
devbox run ct:test

# Test a single chart
CHART=home-assistant devbox run ct:test-chart
```

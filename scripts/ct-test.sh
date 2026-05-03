#!/usr/bin/env bash
set -euo pipefail

CHARTS="${CHART:-}"

if ! kind get clusters | grep -q "^helm-chart-test$"; then
  kind create cluster --config config/kind-config.yaml
fi

echo "=== cluster info ==="

kubectl cluster-info --context kind-helm-chart-test

echo "=== installing local-path-provisioner ==="

if ! kubectl get storageclass local-path &>/dev/null; then
  kubectl apply -f https://raw.githubusercontent.com/rancher/local-path-provisioner/v0.0.35/deploy/local-path-storage.yaml
fi

cleanup() {
  kind delete cluster --name helm-chart-test & wait
  exit 1
}
trap cleanup INT

if [[ -n "$CHARTS" ]]; then
  ct lint-and-install --config config/ct.yaml --charts "charts/${CHARTS}"
else
  ct lint-and-install --config config/ct.yaml --all
fi

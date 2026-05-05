# Helm Charts

[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](https://github.com/junpeng-jp/helm-charts/blob/main/LICENSE)

A collection of Helm charts for self-hosted applications on Kubernetes.

## Usage

[Helm](https://helm.sh) must be installed to use the charts. Please refer to Helm's [documentation](https://helm.sh/docs/) to get started.

```console
helm repo add junpeng-helm-charts https://junpeng-jp.github.io/helm-charts
helm repo update
```

Install a chart:

```console
helm install RELEASE-NAME junpeng-jp/<chart-name>
```

## OCI Registry

> [!NOTE]
> OCI registry support is not yet available and will be added in the future.

## Helm Provenance and Integrity

> [!NOTE]
> GPG signing and chart provenance verification are not yet available and will be added in the future.

## License

[MIT License](https://github.com/junpeng-jp/helm-charts/blob/main/LICENSE).

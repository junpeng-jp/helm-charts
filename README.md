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

# Charts

1. [Home Assistant](./charts/home-assistant/)
2. [Python Matter Server](./charts/python-matter-server/)
3. [Technitium DNS](./charts/technitium/)

# Design Goals

The charts are designed to have standadized value groups so that it can be used in a consistent manner. Take a look at the [`standard.md`](./docs/standard.md) for more information on common helm chart value groups.

All charts have some basic level of unit testing and integration testing.

See [`unit-testing.md`](./docs/unit-testing.md) and [`chart-testing.md`](./docs/chart-testing.md) for more details.

## OCI Registry

> [!NOTE]
> OCI registry support is not yet available and will be added in the future.

## Helm Provenance and Integrity

> [!NOTE]
> GPG signing and chart provenance verification are not yet available and will be added in the future.

## License

[MIT License](https://github.com/junpeng-jp/helm-charts/blob/main/LICENSE).

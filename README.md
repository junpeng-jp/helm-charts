# Jun Peng's Helm Charts

This is a simple repository covering helm charts used for a homelab.

# Charts

1. [Home Assistant](./charts/home-assistant/)
2. [Python Matter Server](./charts/python-matter-server/)
3. [Technitium DNS](./charts/technitium/)

# Design Goals

The charts are designed to have standadized value groups so that it can be used in a consistent manner. Take a look at the [`standard.md`](./docs/standard.md) for more information on common helm chart value groups.

All charts have some basic level of unit testing and integration testing.

See [`unit-testing.md](./docs/unit-testing.md) and [`chart-testing.md`](./docs/chart-testing.md) for more details.

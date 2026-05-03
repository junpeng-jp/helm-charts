# Python Matter Server Helm Chart

A Helm chart for deploying [Python Matter Server](https://github.com/home-assistant-libs/python-matter-server) on Kubernetes.

Python Matter Server is the Matter controller used by Home Assistant to manage Wi-Fi Matter devices and (with a Thread border router) Thread Matter devices.

## Important Components

### 1. Networking — hostNetwork

Python Matter Server requires `hostNetwork: true` for mDNS/Thread discovery.

**On k3s this is mandatory.** k3s uses Flannel as its default CNI, and Flannel's VXLAN overlay does not forward multicast packets. Without `hostNetwork: true`, mDNS-based discovery will not work regardless of any other configuration.

The same applies to any overlay-network CNI (Calico, Cilium in tunnel mode, etc.). If your cluster uses a flat Layer 2 CNI (e.g. Cilium in native routing mode on a flat LAN), you may be able to skip it.

```yaml
hostNetwork: true
dnsPolicy: ClusterFirstWithHostNet  # preserves in-cluster DNS when hostNetwork is on
```

> `dnsPolicy: ClusterFirstWithHostNet` is mandatory alongside `hostNetwork: true`. Without it the pod loses access to in-cluster DNS (Kubernetes Services stop resolving by name).

When `hostNetwork` is enabled, use `nodeSelector` or node affinity to pin the pod to a specific node for consistent LAN interface access.

### 2. Persistence

Python Matter Server stores its state (device commissioning data, fabric credentials) under `/data`. Persistent storage is critical — losing this volume means re-commissioning all Matter devices.

- **Size**: 1Gi is sufficient.
- **Access mode**: `ReadWriteOnce` (single pod).

### 3. Thread / Matter Device Strategy

- **Wi-Fi Matter devices** are handled natively by Python Matter Server over the local LAN — no additional hardware needed.
- **Thread Matter devices** require a Thread border router on your LAN. A cheap option is an Apple HomePod Mini. Only add one if you have or plan to buy Thread Matter devices; don't buy hardware speculatively.

### 4. Relationship to Home Assistant

Deploy Python Matter Server as a separate workload from Home Assistant so each can be restarted, updated, or debugged independently. Home Assistant connects to it over the cluster network via the Matter integration.

| Workload | Kind | Purpose |
|---|---|---|
| **Home Assistant** | StatefulSet | Automation engine and UI |
| **Zigbee2MQTT** | Deployment | Translates Zigbee (Aqara, etc.) to MQTT |
| **Python Matter Server** | Deployment | Matter controller for Wi-Fi (and Thread) Matter devices |

### 5. Resource Limits

Python Matter Server is lightweight at idle. Set memory requests/limits to avoid OOM kills; leave CPU limits generous or unset.

# Home Assistant Helm Chart

A Helm chart for deploying [Home Assistant](https://www.home-assistant.io/) on Kubernetes.

---

## 1. StatefulSet controller

Deploy Home Assistant as a **StatefulSet**. 

StatefulSets provide stable pod identity and predictable PVC naming, which helps to simplify HA setup as it writes its state to disk continuously.

---

## 2. Persistence

Home Assistant stores all configuration, automations, and history under `/config`. 

**Single node setup*** Prefer to use `local-path` provisioner or a direct `hostPath` mount to a directory for configuration storage (e.g. `/opt/home-assistant`). It is fast and handles HA's heavy SQLite write cycles well.

```yaml
persistence:
  enabled: true
  size: 5Gi
  accessModes:
    - ReadWriteOnce
```

---

## 3. Networking

### When to enable hostNetwork

`hostNetwork: true` is required for **LAN multicast/broadcast discovery protocols** — mDNS (HomeKit, Chromecast, Apple TV), SSDP (DLNA), and Matter/Thread. These protocols require the pod to share the host's network interface to join multicast groups.

**On k3s this is effectively mandatory.** k3s uses Flannel as its default CNI, and Flannel's VXLAN overlay drops multicast packets. Without `hostNetwork: true`, mDNS-based discovery and HomeKit will not work regardless of any other configuration. The same applies to any overlay CNI (Calico, Cilium in tunnel mode). Only a flat Layer 2 CNI (e.g. Cilium in native routing mode on a flat LAN) can avoid this requirement.

```yaml
hostNetwork: true
# preserves in-cluster DNS when hostNetwork is on
dnsPolicy: ClusterFirstWithHostNet  
```

HA is exposed via a `ClusterIP` Service on port 8123; an Ingress controller handles external traffic.

When `hostNetwork` is enabled, use `nodeSelector` or node affinity to pin HA to a specific node — both for consistent LAN interface access and to co-locate any USB hardware.

### Default (no hostNetwork)

Standard Kubernetes pod networking works when:

- Devices are reached by IP address (Philips Hue bridge, Shelly, ESPHome, MQTT broker)
- Physical radios are attached via USB (Zigbee/Z-Wave sticks talk to the hardware directly, not over the network)

---

## 4. Hardware / Device Access

### USB device path

Always reference USB serial devices by their stable ID path, not their enumeration index:

```yaml
# Wrong — index changes if other USB devices are plugged in or reordered
/dev/ttyUSB0

# Correct — stable across reboots and re-plugs
/dev/serial/by-id/usb-ITead_Sonoff_Zigbee_3.0_USB_Dongle_Plus_<serial>-if00-port0
```

Mount it as a `hostPath` volume into the Zigbee2MQTT pod (see [Companion Deployments](#10-companion-deployments)). Node affinity or `nodeSelector` must pin that pod to the node with the dongle attached.

### Security context options

Accessing a serial device requires the container to have permission to open the device file. Options, from least to most privileged:

**Option 1 — supplementalGroups (recommended)**

Serial devices are typically owned by the `dialout` group (GID 20 on Debian/Ubuntu). Add that GID to the pod without granting any extra capabilities:

```yaml
securityContext:
  runAsNonRoot: true
  supplementalGroups: [20]   # dialout group — owns /dev/tty* and serial/by-id/* on the host
```

This is the least privileged option: the container runs as a non-root user, gains no Linux capabilities, and can only open device files that the `dialout` group has read/write access to. Verify the host GID with `stat /dev/serial/by-id/<your-device>`.

**Option 2 — privileged: true (simple, but broad)**

```yaml
securityContext:
  privileged: true
```

Grants full access to the host kernel — equivalent to running as root on the node. Works unconditionally, but a compromised container with `privileged: true` can escape to the host. Start with Option 1 and fall back here only if host permissions cannot be changed.

---

## 5. Ingress

HA's frontend uses persistent WebSocket connections; the ingress must not close idle connections. Use a `ClusterIP` Service and a standard `networking.k8s.io/v1` Ingress:

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: home-assistant
  annotations:
    # --- nginx ingress controller ---
    # Traefik handles WebSockets automatically; remove these two lines for Traefik.
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    # --- TLS (both controllers, requires cert-manager) ---
    cert-manager.io/cluster-issuer: letsencrypt-prod
spec:
  ingressClassName: nginx   # change to "traefik" for a Traefik cluster
  tls:
    - hosts:
        - ha.example.com
      secretName: home-assistant-tls
  rules:
    - host: ha.example.com
      http:
        paths:
          - path: /
            pathType: Prefix
            backend:
              service:
                name: home-assistant
                port:
                  number: 8123
```

### Trusted proxy configuration (required)

When HA sits behind a reverse proxy it must be told to trust `X-Forwarded-For` headers, otherwise it logs the ingress controller's IP as the source for every request and its IP-ban feature can block the controller. Add this to `configuration.yaml`:

```yaml
http:
  use_x_forwarded_for: true
  trusted_proxies:
    - 10.0.0.0/8   # replace with your cluster's pod/service CIDR
```

### External access

Do not expose port 8123 directly to the internet. Route external access through a VPN tunnel (e.g. WireGuard) pointed at the node, then reach HA through the Ingress over the tunnel. This avoids maintaining a public port forward and keeps the attack surface minimal. Webhooks under `/api/webhook/` are served by the same Ingress rule — no second Ingress is needed for those.

---

## 6. Customization

**Init containers** can handle pre-startup tasks such as copying default config files into the PVC on first boot or waiting for an MQTT broker to be ready.

**Environment variables and secrets** — set `TZ` for the correct timezone. Inject database URLs, API keys, and tokens via Kubernetes Secrets rather than committing them to `configuration.yaml`.

**Monitoring** — a `ServiceMonitor` resource enables Prometheus scraping of HA metrics. Requires the Prometheus integration to be enabled inside Home Assistant.

---

## 7. Companion Deployments (Decoupled Architecture)

Do not run Zigbee support inside the HA container. Deploy Zigbee2MQTT as a separate workload so it can be restarted, updated, or debugged independently without taking HA down.

| Workload | Kind | Purpose |
|---|---|---|
| **Home Assistant** | StatefulSet | Automation engine and UI |
| **Zigbee2MQTT** | Deployment | Translates Zigbee (Aqara, etc.) to MQTT. Mounts the USB dongle. Needs the `dialout` security context. |

**Firmware:** Keep the Sonoff dongle on **Zigbee-only (Z-Stack) firmware**. Multi-PAN (Zigbee + Thread on one stick) firmware is not stable enough for a production home environment.

**In-cluster DNS dependency:** If you run a custom DNS server (e.g. Technitium) inside the same cluster that HA depends on, configure a fallback external resolver (e.g. `1.1.1.1`) on the host itself. If k3s crashes, the host needs to reach the internet to pull images required to recover the cluster — it cannot do that if its only DNS is the cluster it is trying to restart.

---

## 8. Resource Limits

Home Assistant is not CPU-hungry at idle, but history recording and large automation runs can spike usage.

- Set memory `requests`/`limits` to avoid OOM kills.
- Leave CPU limits generous or unset to avoid throttling automations.

---

## 9. Backups

Treat the cluster as ephemeral but the data as permanent. What needs backing up:

| What | Why |
|---|---|
| `/config` (HA config directory) | Automations, integrations, history database |
| Zigbee2MQTT data directory | Device pairing state and network map |
| Helm values / Helmfile manifests | Already in Git — no separate backup needed |

**Recommended pipeline:** Install `restic` on the host and write a bash script that backs up the `hostPath` or `local-path` volume directories directly to an S3-compatible bucket (Cloudflare R2 has no egress fees, which makes restore testing free). Run it via a standard Linux cron job nightly.

Store the Restic repository password and any VPN private keys somewhere physical and offline. If the node's drive dies, recovery time with this setup is however long it takes to provision a new node, run an Ansible playbook, and pull the latest snapshot.

---

## Reference

Upstream chart: [pajikos/home-assistant-helm-chart](https://github.com/pajikos/home-assistant-helm-chart)

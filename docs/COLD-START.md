# Cold Start Manual Steps

This document lists all manual steps required to bring up a new system from
scratch that are not handled by NixOS or automation. Each step is annotated
in-line in the relevant config with `# COLD START:` and described here in
detail.

If you are deploying a new system, follow these steps exactly. If you add or
remove a cold start step, update this document and the relevant code comments.

---

## 1. Create ZFS Dataset for Prometheus

**Context:** Prometheus stores its data in `/var/lib/prometheus2` by default.
This directory should be a ZFS dataset, created and mounted before Prometheus
will start. The dataset name (e.g., `fastdisk/prometheus`) must be set in the
host configuration for snapshot automation.

**Step-by-step:**

1. Create the ZFS dataset (replace `fastdisk` with your pool name):

   ```sh
   zfs create -o mountpoint=/var/lib/prometheus2 fastdisk/prometheus
   ```

1. Verify the dataset is mounted:

   ```sh
   zfs list
   ls -ld /var/lib/prometheus2
   ```

1. Set the dataset name in your host config for snapshot automation:

   ```nix
   services.prometheusZfsSnapshot.dataset = "fastdisk/prometheus";
   ```

1. If restoring from backup, see the restore section in `OBSERVABILITY.md`.

**In config:**

- `hosts/skaia/observability.nix` — look for
  `services.prometheusZfsSnapshot.dataset = "fastdisk/prometheus";`

---

## 2. Thermal Management Setup

**Context:** Some systems require manual installation of firmware or
configuration for thermal management (e.g., fan control, sensor modules).

**Step-by-step:**

1. Identify required kernel modules or firmware for your hardware (e.g.,
   `nct6775` for Super I/O sensors).
1. If firmware is not available in NixOS, download and install it manually:

   ```sh
   # Example: copy firmware to /lib/firmware or /run/current-system/firmware
   cp firmware-file /lib/firmware/
   ```

1. Load the kernel module:

   ```sh
   modprobe nct6775
   ```

1. Install and run `lm_sensors` to detect sensors:

   ```sh
   nix-shell -p lm_sensors --run sensors-detect
   # Accept defaults unless you know your hardware
   sudo sensors-detect
   sudo systemctl restart systemd-modules-load.service
   sensors
   ```

1. If you have PWM-controlled fans, run `pwmconfig` to generate a fancontrol
   config:

   ```sh
   sudo pwmconfig
   # This will interactively test your fans and write a config file
   # You may need to copy the config to the correct location or update your Nix config
   ```

1. If additional configuration is needed, document it here.

**In config:**

- Add `# COLD START: Requires manual firmware/module setup for thermal
  management` where relevant.
- See `hosts/skaia/thermal.nix` for example configuration and comments.

---

## 3. K3s Prometheus Client Credentials

**Context:** Prometheus scrapes Kubernetes metrics using a client certificate
and key extracted from k3s. This is handled by a systemd service, but requires
k3s to be running and accessible.

**Step-by-step:**

1. Ensure k3s is installed and running on the system.
1. If `/var/lib/prometheus-k3s/client.crt` and
   `/var/lib/prometheus-k3s/client.key` do not exist, run the following systemd
   service:

   ```sh
   sudo systemctl start k3s-token-for-prometheus.service
   ```

   This will extract the credentials from the k3s kubeconfig and place them in
   the correct location for Prometheus.
1. If the service fails, check that k3s is healthy and accessible with
   `kubectl get nodes`.

**In config:**

- See `hosts/skaia/k3s/k3s-token.nix` for the service definition.

---

## 4. Create ZFS Dataset for Docker Registry

**Context:** The local Docker registry (`registry:2` via NixOS
`services.dockerRegistry`) stores its layers under `/var/lib/registry`. This
 directory must be backed by a ZFS dataset so that images are not kept on the
root filesystem and can benefit from snapshots.

**Step-by-step:**

1. Create the dataset on the slow disk pool:

   ```sh
   zfs create -o mountpoint=/var/lib/registry slowdisk/registry
   ```

1. Verify the dataset is mounted:

   ```sh
   zfs list slowdisk/registry
   ls -ld /var/lib/registry
   ```

1. (Optional) Set a quota or reservation if you want to limit/guarantee
   space, for example 150 GiB:

   ```sh
   zfs set quota=150G slowdisk/registry
   ```

**In config:**

- `hosts/skaia/default.nix` — look for
  `# COLD START: Requires ZFS dataset slowdisk/registry` next to the
  `services.dockerRegistry` block.

---

## 5. Move LAN DNS to `skaia`

**Context:** The home router may not support the desired static records for the
`veil.home.arpa` zone. DNS will be hosted on `skaia` while Skaia continues to
use NetworkManager for its own connectivity.

**Step-by-step:**

1. Configure a DNS service on `skaia` (e.g., unbound) to:
   - Bind to `192.168.0.160` and `127.0.0.1`
   - Serve the zone `veil.home.arpa` with static records
     (e.g., `ingress.veil.home.arpa` → `192.168.0.220`)
   - Forward other queries to upstream resolvers (router or public)
1. Open firewall on `skaia` for TCP/UDP 53.
1. Update the router's DHCP settings so the LAN DNS server is
   `192.168.0.160`.
1. Validate from a LAN client with
   `dig +short @192.168.0.160 ingress.veil.home.arpa`.

**In config:**

- Add `# COLD START: Router DHCP must be updated to point LAN DNS to
  192.168.0.160` near Skaia's DNS service definition when added.

---

## 6. Set networking.hostId per host

**Context:** `networking.hostId` is used by ZFS and system components to uniquely
identify a host. Placeholder values should be replaced with real IDs on first
install.

**Step-by-step (preferred on ZFS systems):**

1. Generate a hostid (8 hex chars) and write `/etc/hostid`:

   ```sh
   # Use the kernel's hostid if present
   hostid | cut -c1-8
   # Or generate a deterministic one from machine-id:
   dd if=/etc/machine-id bs=4 count=1 2>/dev/null | hexdump -e '1/4 "%08x" "\n"'
   ```

1. Copy the value into the host's Nix config:

   ```nix
   networking.hostId = "<8-hex-chars>";
   ```

1. Rebuild the system.

**Notes:**

- Ensure each meteor has a unique hostId.
- If using ZFS, `hostid` must match across boots for import pools.

**In config:**

- See `hosts/meteor-*/default.nix` lines with `# COLD START: set a unique hostId`.

---

## 7. TODO: Secrets Management

> TODO: Document all secrets required for cold start (e.g., API keys, passwords
> in `/etc/nixos/secrets/`). For now, ensure any referenced secret files exist
> and are populated as needed on new systems.

---

## 8. [Add future cold start steps here]

If you discover a new manual step, document it in-line and add a section here
with explicit, actionable instructions.

---

## 9. Veil Cluster Cold Start (meteors)

Context: Bring up the HA k3s cluster (veil) across `meteor-1..3`.

Step-by-step:

1. Ensure DHCP reservations exist for `meteor-1..3` and the MetalLB pool is
   reserved and outside DHCP. See `docs/residence-1/ADDRESSING.md`.
1. Create the k3s join token secret on the build host and make it available on
   each meteor at `/etc/nixos/secrets/veil-k3s-token`:

   ```sh
   head -c 48 /dev/urandom | base64 | tr -d '\n' > secrets/veil-k3s-token
   git secret add secrets/veil-k3s-token
   git secret hide
   # copy revealed file to each host securely or reveal on-host using your GPG key
   ```

1. Bootstrap `meteor-1` first:
   - Build and switch: `sudo nixos-rebuild switch --flake /etc/nixos#meteor-1`
   - This node runs k3s with `--cluster-init`.
   - Verify readiness: `sudo k3s kubectl get nodes`

1. Bootstrap `meteor-2` and `meteor-3` next:
   - Build and switch: `sudo nixos-rebuild switch --flake /etc/nixos#meteor-2`
   - and `meteor-3` similarly
   - These nodes join via `--server https://192.168.0.121:6443` and token.

1. Verify etcd and cluster health:

   ```sh
   sudo k3s kubectl get nodes -o wide
   sudo k3s kubectl get --raw "/readyz?verbose"
   ```

1. Install cluster services (managed by FluxCD). See Section 9 for Flux
   bootstrap and apply order.

In config:

- See `hosts/meteor-1/k3s/default.nix` and common flags in
  `modules/veil/k3s-common.nix`.
- See `hosts/meteor-2/k3s/default.nix` and `hosts/meteor-3/k3s/default.nix`.

---

## 10. FluxCD Bootstrap for Veil (GitOps)

**Context:** Flux controllers reconcile Helm releases from Git, removing any
single-node dependency and providing versioned, declarative installs.

**Step-by-step:**

1. Install Flux controllers (one-time per cluster):

   ```bash
   kubectl create ns flux-system || true
   kubectl apply -f \
     https://github.com/fluxcd/flux2/releases/latest/download/install.yaml
   kubectl -n flux-system get pods
   ```

1. Apply HelmRepository sources for required charts:

   ```bash
   # Apply repo sources from this repository once added, for example:
   kubectl apply -f flux/veil/helm-repos.yaml
   ```

1. Apply services via HelmRelease (and MetalLB IP resources):

   ```bash
   # MetalLB controller
   kubectl apply -f flux/veil/metallb.yaml
   # MetalLB address pool + L2Advertisement
   kubectl apply -f flux/veil/metallb-pool.yaml
   # ingress-nginx controller
   kubectl apply -f flux/veil/ingress-nginx.yaml
   # kube-prometheus-stack
   kubectl apply -f flux/veil/monitoring.yaml
   ```

1. Verify reconciliation and health:

   ```bash
   kubectl get hr -A
   kubectl -n flux-system get kustomizations.sources.toolkit.fluxcd.io
   kubectl -n metallb-system get ipaddresspools,l2advertisements
   kubectl -n ingress-nginx get svc
   kubectl -n monitoring get pods
   ```

**In config:**

- Add `# COLD START: FluxCD bootstrap required before cluster services
  reconcile` near any references to Flux-managed services or docs.

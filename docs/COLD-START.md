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

---

## 11. MinIO Root Credentials (object-store namespace)

**Context:** The MinIO HelmRelease references an existing Secret for the root
user. This secret must be created manually before the first deploy to avoid
crashloop.

**Step-by-step:**

1. Create the namespace if it does not exist:

   ```sh
   kubectl create ns object-store || true
   ```

1. Create the secret with root user and password:

   ```sh
   kubectl -n object-store create secret generic minio-root \
     --from-literal=root-user="minioadmin" \
     --from-literal=root-password="<change-me>"
   ```

1. After the secret exists, Flux will roll out MinIO automatically after you
   commit and push the HelmRelease.

**In config:**

- See `flux/veil/minio.yaml` for the HelmRelease and `auth.existingSecret`.

---

## 11. User Cache on Separate ZFS Dataset (no nesting under $HOME)

**Context:** `~/.cache` can grow large and is not worth keeping in ZFS
snapshots. To avoid login races and nested filesystem ordering issues, mount
the cache dataset outside `$HOME` and point `XDG_CACHE_HOME` to it.

**Step-by-step:**

1. Create the dataset with a legacy mountpoint and disable autosnapshots:

   ```sh
   zfs create -o mountpoint=legacy fastdisk/user/home/dlk-cache
   zfs set com.sun:auto-snapshot=false fastdisk/user/home/dlk-cache
   ```

1. Add a persistent mount for the cache outside `$HOME` in the host config:

   ```nix
   # hosts/skaia/default.nix
   # COLD START: Create ZFS dataset fastdisk/user/home/dlk-cache with legacy
   # mountpoint and disable autosnapshots on it. Mount outside $HOME.
   fileSystems."/fastcache/dlk" = {
     device = "fastdisk/user/home/dlk-cache";
     fsType = "zfs";
   };
   ```

1. Rebuild and switch to activate the mount:

   ```sh
   sudo nixos-rebuild switch --flake /etc/nixos#skaia
   ```

1. Create the mountpoint and set ownership:

   ```sh
   sudo mkdir -p /fastcache/dlk
   sudo chown -R dlk:users /fastcache/dlk
   ```

1. Point the user cache to the new location (Home Manager):

   ```nix
   # home/default.nix
   xdg.cacheHome = "/fastcache/dlk";
   ```

**Recovering space from past snapshots:**

Moving the cache prevents future snapshots from including it, but existing
snapshots may still hold space. Review and destroy old snapshots as needed:

```sh
# Inspect snapshot usage at the home dataset level
zfs get used,usedbysnapshots fastdisk/user/home/dlk

# List snapshots with sizes (oldest first)
zfs list -t snapshot -o name,used,creation -s creation \
  fastdisk/user/home/dlk | cat

# Destroy specific snapshots you no longer need (example)
sudo zfs destroy fastdisk/user/home/dlk@auto-2025-09-10-1200

# Or destroy a range after careful review (example shows first 10)
# WARNING: This is irreversible; confirm names before running
zfs list -H -t snapshot -o name -s creation fastdisk/user/home/dlk | \
  sed -n '1,10p' | xargs -n1 sudo zfs destroy
```

**In config:**

- See `hosts/skaia/default.nix` for the `fileSystems."/home/dlk/.cache"` entry
  and the `# COLD START:` annotation.

---

## 12. Router Port Forwards for `skaia` Ingress

**Context:** External access to public web content and Teleport passes through
the TP-Link AC2300 router. The router must forward specific TCP ports to
`skaia` before these services become reachable from the internet.

**Step-by-step:**

1. Sign in to the router admin UI (default `http://192.168.0.1`) with an admin
   account.
1. Navigate to **NAT Forwarding → Virtual Servers**.
1. Add or update entries so that:
   - TCP `80` → `192.168.0.160` (`skaia`, nginx HTTP)
   - TCP `443` → `192.168.0.160` (`skaia`, nginx HTTPS)
   - TCP `3023` → `192.168.0.160` (`skaia`, Teleport proxy)
   - TCP `3024` → `192.168.0.160` (`skaia`, Teleport reverse tunnel)
1. Save changes and confirm the new rules are active. The router may require a
   reboot to apply updates.
1. Ensure public DNS records point at the router's WAN IP. `ddclient` updates
   `valueof.info`, `teleport.valueof.info`, and `urbit.valueof.info`
   automatically once secrets are in place.
1. Verify externally by connecting through a non-LAN network (e.g., mobile
   hotspot) and running:

   ```sh
   curl -I http://valueof.info/
   curl -I https://teleport.valueof.info/
   tsh login --proxy teleport.valueof.info:443
   # Confirm reverse tunnel port is reachable
   nc -vz valueof.info 3024
   ```

**In config:**

- `hosts/skaia/nginx.nix` — see the `# COLD START:` comment preceding the nginx
  service.
- `hosts/skaia/teleport.nix` — see the `# COLD START:` comment preceding the
  Teleport service.

---

## 13. Teleport Cluster Bootstrap

**Context:** Teleport provides authenticated access (SSH, Kubernetes, web apps).
The initial admin user and node enrollments require manual steps.

**Step-by-step:**

1. After deploying `skaia` with Teleport enabled, create the storage directory
   if it does not exist (usually handled automatically):

   ```sh
   sudo install -d -m 700 /var/lib/teleport
   ```

1. Generate the first administrator:

   ```sh
   sudo tctl users add <admin-user> --roles=editor,access
   ```

   This prints a one-time invitation URL such as
   `https://teleport.valueof.info/web/invite/...`. Open it in a browser (the
   request stays on nginx with an ACME certificate) or continue via CLI in the
   next step.

1. Log in from your workstation (or from `skaia` for the first run):

   ```sh
   tsh login --proxy teleport.valueof.info:443 --user=<admin-user>
   ```

   If the invite was completed in the browser, `tsh login` should proceed
   without additional prompts. This step only provisions Teleport credentials
   for the user; node enrollment happens separately.

1. Grant each user the Unix logins they should be allowed to assume. Without
   this, SSH and Kubernetes access will be denied even though the user can
   authenticate:

   ```sh
   sudo tctl users update <admin-user> --set-logins=dlk,root
   # repeat for any additional users
   ```

   After changing roles or logins, have the user re-run `tsh logout` and
   `tsh login ...` so new certificates pick up the updated traits.

1. Grant Kubernetes RBAC for Teleport-issued credentials. For quick
   administrative access you can map the user into `system:masters`:

   ```sh
   sudo tctl users update <admin-user> --set-kubernetes-groups=system:masters
   ```

   Re-login with `tsh logout`/`tsh login` to refresh certificates.

1. For each server you want in Teleport (e.g., `skaia`, `meteor-*`), mint a
   one-time join token and stage it on the host before rebuilding:

   ```sh
   # Example for meteor-1 (repeat for each host, adjusting names)
   sudo tctl tokens add --type=node --format=text --ttl=30m \
     --labels=host=meteor-1 > /etc/nixos/secrets/teleport/meteor-1.token

   sudo chmod 600 /etc/nixos/secrets/teleport/meteor-1.token
   sudo chown root:root /etc/nixos/secrets/teleport/meteor-1.token
   scp /etc/nixos/secrets/teleport/meteor-1.token \
     meteor-1.home.arpa:/etc/nixos/secrets/teleport/meteor-1.token
   ```

   Rebuild the host (`sudo nixos-rebuild switch --flake /etc/nixos#meteor-1`)
   so `custom.teleportNode.enable = true` starts the `teleport` systemd unit.
   If the token file is empty or missing, the service starts using cached creds.

1. Verify from the Teleport auth server that the node registered. On `skaia`:

   ```sh
   sudo systemctl status teleport
   tsh ls
   ```

   Nodes running `custom.teleportNode` will show up alongside the proxy host.

1. Once a node appears, wipe the token file to avoid storing long-lived join
   secrets:

   ```sh
   sudo truncate -s0 /etc/nixos/secrets/teleport/meteor-1.token
   ```

**In config:**

- `hosts/skaia/teleport.nix` contains the Teleport service definition and
  `# COLD START:` notes.
- Future host-specific Teleport agent modules should add their own `# COLD START`
  comments referencing the join token requirement.

1. Test Kubernetes access via Teleport once the kubernetes service is enabled on
   `skaia`:

   ```sh
   tsh kube login skaia
   tsh kubectl -n default get pods
   ```

   If this fails, confirm the user has the expected Kubernetes groups and
   that `skaia` can reach the k3s API on port `6443`.

1. The Teleport pre-start hook normalizes the copied k3s kubeconfig so the
   cluster/context is named `skaia`. If you ever need to rotate the kubeconfig
   manually, copy the raw k3s config and replace every `name: default`,
   `cluster: default`, and `user: default` with `skaia`, then ensure
   `current-context: skaia`.

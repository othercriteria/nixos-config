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

## 5. TODO: Secrets Management

> TODO: Document all secrets required for cold start (e.g., API keys, passwords
> in `/etc/nixos/secrets/`). For now, ensure any referenced secret files exist
> and are populated as needed on new systems.

---

## 6. [Add future cold start steps here]

If you discover a new manual step, document it in-line and add a section here
with explicit, actionable instructions.

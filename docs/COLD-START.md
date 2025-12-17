# Cold Start Manual Steps

This document lists all manual steps required to bring up a new system from
scratch that are not handled by NixOS or automation. Each step is annotated
in-line in the relevant config with `# COLD START:` and described here in
detail.

If you are deploying a new system, follow these steps exactly. If you add or
remove a cold start step, update this document and the relevant code comments.

---

## 0. GPG Key Setup (prerequisite for secrets)

**Context:** Many cold start steps require `make reveal-secrets` which uses
git-secret to decrypt sensitive files. git-secret requires the GPG private key
to be available on the host. This step must be completed before any step that
needs revealed secrets.

**Applies to:** All hosts that need access to encrypted secrets (meteors, hive,
any new server).

**Preparation (on a trusted host with your GPG key):**

1. Export GPG keys if not already done:

   ```sh
   gpg --export -a othercriteria@gmail.com > ~/gnupg-public.asc
   gpg --export-secret-keys -a othercriteria@gmail.com > ~/gnupg-secret.asc
   gpg --export-ownertrust > ~/gnupg-ownertrust.txt
   ```

1. Copy to the target host:

   ```sh
   scp ~/gnupg-*.asc ~/gnupg-ownertrust.txt <target-host>:~/
   ```

**On the target host (headless/SSH session):**

1. Enter a nix-shell with pinentry for terminal use:

   ```sh
   nix-shell -p gnupg pinentry-tty
   ```

1. Configure gpg-agent to use terminal pinentry and import keys:

   ```sh
   mkdir -p ~/.gnupg
   echo "pinentry-program $(which pinentry-tty)" > ~/.gnupg/gpg-agent.conf
   gpgconf --kill gpg-agent
   export GPG_TTY=$(tty)
   gpg --import ~/gnupg-public.asc
   gpg --import ~/gnupg-secret.asc
   gpg --import-ownertrust ~/gnupg-ownertrust.txt
   ```

   You will be prompted for your GPG passphrase when importing the secret key.

1. Verify the key is available:

   ```sh
   gpg --list-secret-keys
   ```

1. Exit the nix-shell and test secret reveal:

   ```sh
   exit
   cd /etc/nixos && make reveal-secrets
   ```

1. Clean up exported keys from the target host:

   ```sh
   rm ~/gnupg-*.asc ~/gnupg-ownertrust.txt
   ```

**Notes:**

- The `pinentry-tty` configuration persists in `~/.gnupg/gpg-agent.conf`
- If you later use a graphical session, you may want to switch to
  `pinentry-gtk-2` or `pinentry-gnome3`
- The GPG agent caches the passphrase, so subsequent operations won't prompt

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

Context: Bring up the HA k3s cluster (veil) across `meteor-1..4`.

### Initial cluster bootstrap (one-time)

1. Ensure DHCP reservations exist for all meteors and the MetalLB pool is
   reserved and outside DHCP. See `docs/residence-1/ADDRESSING.md`.

1. Generate the k3s join token (one-time, already done):

   ```sh
   head -c 48 /dev/urandom | base64 | tr -d '\n' > secrets/veil-k3s-token
   git secret add secrets/veil-k3s-token
   git secret hide
   ```

1. Bootstrap `meteor-1` first (runs with `--cluster-init`), then other nodes.

### Adding a new meteor node

1. Boot from NixOS installer and complete base installation.

1. Clone the config repo and reveal secrets:

   ```sh
   sudo git clone https://github.com/othercriteria/nixos-config.git /etc/nixos
   cd /etc/nixos && sudo git secret reveal
   ```

   The k3s join token at `/etc/nixos/secrets/veil-k3s-token` is now in place.

1. Generate a unique hostId and update the host config:

   ```sh
   HOSTID=$(dd if=/dev/urandom bs=4 count=1 2>/dev/null | hexdump -e '1/4 "%08x" "\n"')
   sudo sed -i "s/FIXME000/$HOSTID/" /etc/nixos/hosts/meteor-N/default.nix
   ```

1. Build and switch:

   ```sh
   sudo nixos-rebuild switch --flake /etc/nixos#meteor-N
   ```

1. Verify cluster membership:

   ```sh
   k3s kubectl get nodes -o wide
   k3s kubectl get --raw "/readyz?verbose"
   ```

1. If a stale node appears (e.g., from the installer hostname), delete it:

   ```sh
   k3s kubectl delete node nixos
   ```

**In config:**

- See `hosts/meteor-1/k3s/default.nix` (initial node with `--cluster-init`)
- See `hosts/meteor-{2,3,4}/k3s/default.nix` (join via meteor-1)
- Common flags in `modules/veil/k3s-common.nix`

---

## 10. FluxCD Bootstrap for Veil (GitOps)

**Context:** Flux controllers reconcile Helm releases from a private Git repo
(`gitops-veil`), providing versioned, declarative cluster management. The repo
appears in-tree as a submodule for local editing.

### Prerequisites

- SSH key with access to `github.com:othercriteria/gitops-veil.git`
- `kubectl` configured for the veil cluster

### Step-by-step

1. Initialize the `gitops-veil` submodule (for local editing):

   ```bash
   make add-gitops-veil
   ```

1. Install Flux controllers (one-time per cluster):

   ```bash
   kubectl create ns flux-system || true
   kubectl apply -f \
     https://github.com/fluxcd/flux2/releases/latest/download/install.yaml
   kubectl -n flux-system get pods
   ```

1. Create the deploy key for Flux to pull from the private repo:

   ```bash
   # Generate a deploy key (do this once, store securely)
   ssh-keygen -t ed25519 -f /tmp/gitops-veil-deploy -N ""

   # Add the public key to GitHub repo Settings > Deploy keys (read-only)
   cat /tmp/gitops-veil-deploy.pub

   # Create the secret in-cluster
   kubectl -n flux-system create secret generic gitops-veil-deploy-key \
     --from-file=identity=/tmp/gitops-veil-deploy \
     --from-literal=known_hosts="github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl"

   # Clean up local key
   rm /tmp/gitops-veil-deploy /tmp/gitops-veil-deploy.pub
   ```

1. Apply the GitOps bootstrap (GitRepository + Kustomization):

   ```bash
   kubectl apply -f gitops-veil/bootstrap/
   ```

1. Verify Flux is reconciling:

   ```bash
   kubectl -n flux-system get gitrepositories,kustomizations
   kubectl get hr -A
   ```

### Workflow after bootstrap

Edit manifests locally in `gitops-veil/`, then:

```bash
cd gitops-veil
git add . && git commit -m "description" && git push
# Flux auto-reconciles within ~1 minute
```

Watch reconciliation:

```bash
kubectl -n flux-system get kustomizations -w
```

**In config:**

- `gitops-veil/` submodule contains all veil cluster manifests
- `gitops-veil/bootstrap/` contains the GitRepository and Kustomization that
  point Flux at the repo itself

---

## 11. cert-manager CA Secret

**Context:** cert-manager uses a ClusterIssuer (`home-ca`) to sign TLS
certificates for cluster services. The CA key is stored encrypted in
`secrets/home-ca.key` (revealed via `make reveal-secrets`).

**Step-by-step:**

1. Ensure secrets are revealed:

   ```bash
   make reveal-secrets
   ```

1. Create the CA secret in-cluster:

   ```bash
   kubectl create ns cert-manager || true
   kubectl -n cert-manager create secret tls home-ca-secret \
     --cert=secrets/home-ca.crt \
     --key=secrets/home-ca.key
   ```

**In config:**

- `secrets/home-ca.crt` and `secrets/home-ca.key` (encrypted via git-secret)
- `gitops-veil/public/cert-manager.yaml` defines the ClusterIssuer `home-ca`
- Ingresses use annotation `cert-manager.io/cluster-issuer: "home-ca"`

---

## 12. MinIO Root Credentials (object-store namespace)

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

## 13. User Cache on Separate ZFS Dataset (no nesting under $HOME)

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

## 14. Router Port Forwards for `skaia` Ingress

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

## 15. Teleport Cluster Bootstrap

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

---

## 16. ArgoCD Repository Credentials

**Context:** ArgoCD needs SSH credentials to access private Git repositories.
The SSH key is stored encrypted in `secrets/argocd-repo-key`.

**Step-by-step:**

1. Ensure secrets are revealed:

   ```bash
   make reveal-secrets
   ```

1. Create the ArgoCD repository secret:

   ```bash
   kubectl -n argocd create secret generic argocd-repo-creds \
     --from-literal=type=git \
     --from-literal=url=git@github.com:othercriteria \
     --from-file=sshPrivateKey=secrets/argocd-repo-key
   kubectl -n argocd label secret argocd-repo-creds \
     argocd.argoproj.io/secret-type=repo-creds
   ```

   This creates a credential template that matches all repos under the
   `othercriteria` GitHub account.

1. Verify in ArgoCD UI: Settings → Repository certificates and known hosts
   should show the credential, and you can now add Applications pointing to
   private repos.

**In config:**

- `secrets/argocd-repo-key` — SSH private key (encrypted via git-secret)
- The secret uses `repo-creds` type (credential template) rather than a
  per-repo secret, so it applies to all matching repos automatically

---

## 17. Docker Registry (in-cluster)

**Context:** The veil cluster runs an in-cluster Docker Registry for container
images, using MinIO as the S3 backend.

**Step-by-step:**

1. Create the MinIO bucket for registry storage (via MinIO Console at
   `https://s3-console.veil.home.arpa` or `mc` CLI):

   ```bash
   # Using mc CLI (configure alias first)
   mc mb minio/registry
   ```

1. Create the registry namespace and S3 credentials secret:

   ```bash
   kubectl create ns registry

   # Use the same credentials as MinIO root (or create a dedicated user)
   kubectl -n registry create secret generic registry-s3 \
     --from-literal=s3AccessKey="minioadmin" \
     --from-literal=s3SecretKey="<minio-root-password>"
   ```

1. The registry will be available at `https://registry.veil.home.arpa` once
   Flux reconciles.

1. To push images from a meteor node:

   ```bash
   docker tag myimage:latest registry.veil.home.arpa/myimage:latest
   docker push registry.veil.home.arpa/myimage:latest
   ```

**In config:**

- `gitops-veil/public/registry.yaml` — HelmRelease for Docker Registry
- Uses MinIO S3 backend via `s3.veil.home.arpa` (external ingress)
- TLS via cert-manager (home CA trusted by all nodes)

---

## 18. Harmonia Binary Cache Signing Key

**Context:** Harmonia serves the nix store from `skaia` to other LAN hosts. It
signs cached derivations with a private key; clients verify with the
corresponding public key.

**Step-by-step:**

1. Generate the signing keypair (one-time, from the repo root):

   ```sh
   nix-store --generate-binary-cache-key cache.home.arpa \
     secrets/harmonia-cache-private-key \
     assets/harmonia-cache-public-key.txt
   ```

   The public key file will contain something like:

   ```text
   cache.home.arpa:AbCdEf123...base64...==
   ```

1. Add the private key to git-secret and encrypt:

   ```sh
   git secret add secrets/harmonia-cache-private-key
   git secret hide
   ```

1. Commit both files:

   ```sh
   git add secrets/harmonia-cache-private-key.secret \
           assets/harmonia-cache-public-key.txt \
           .gitignore
   git commit -m "feat: add harmonia binary cache signing keys"
   ```

1. Deploy to `skaia`:

   ```sh
   make reveal-secrets
   make apply-host HOST=skaia
   ```

1. Verify Harmonia is serving:

   ```sh
   curl -I http://cache.home.arpa/nix-cache-info
   ```

   Expected output includes `StoreDir: /nix/store` and `Priority: 30`.

1. Deploy to meteors to pick up the new substituter config:

   ```sh
   make apply-host HOST=meteor-1
   # repeat for other hosts
   ```

1. Test that meteors use the cache by building something available on skaia:

   ```sh
   # On a meteor, with nix verbose output
   nix build nixpkgs#hello --print-build-logs -v 2>&1 | grep cache.home.arpa
   ```

**In config:**

- `modules/harmonia.nix` — service definition (skaia only)
- `hosts/skaia/nginx.nix` — reverse proxy for `cache.home.arpa`
- `hosts/skaia/unbound.nix` — DNS record for `cache.home.arpa`
- `hosts/server-common/default.nix` — substituter config for meteor nodes
- `assets/harmonia-cache-public-key.txt` — public key (plain text, committed)
- `secrets/harmonia-cache-private-key` — private key (git-secret encrypted)

---

## 19. Hive Migration and Bootstrap

**Context:** `hive` is a headless server running Urbit. It streams metrics and
logs to `skaia` for centralized observability.

**Prerequisites:**

- Existing hive system with LUKS-encrypted root, storage mounts
- Old config archived at `~/configuration.nix.old` on hive

**Migration steps:**

1. Clone the config repo on hive:

   ```sh
   sudo git clone https://github.com/othercriteria/nixos-config.git /etc/nixos
   cd /etc/nixos && sudo make reveal-secrets
   ```

1. Create the Teleport token directory and generate a join token on skaia:

   ```sh
   # On skaia
   sudo tctl tokens add --type=node --ttl=1h --format=text > /tmp/hive.token

   # Copy to hive
   ssh hive.home.arpa 'sudo mkdir -p /etc/nixos/secrets/teleport'
   scp /tmp/hive.token hive.home.arpa:/tmp/
   ssh hive.home.arpa 'sudo mv /tmp/hive.token /etc/nixos/secrets/teleport/ && \
     sudo chmod 600 /etc/nixos/secrets/teleport/hive.token'
   rm /tmp/hive.token
   ```

1. Build and switch on hive:

   ```sh
   sudo nixos-rebuild switch --flake /etc/nixos#hive
   ```

1. Verify services:

   ```sh
   # SSH and Teleport
   systemctl status sshd teleport-node

   # Observability (metrics stream to skaia)
   systemctl status prometheus-node-exporter netdata promtail

   # Check netdata is streaming to skaia
   journalctl -u netdata | grep -i stream
   ```

1. Verify in skaia's observability:

   ```sh
   # Prometheus should show hive target
   curl -s localhost:9001/api/v1/targets | jq '.data.activeTargets[] | select(.labels.job=="hive")'

   # Netdata dashboard should show hive as a child node
   # Visit netdata.home.arpa and look for hive in the node list
   ```

1. Truncate the Teleport token after successful join:

   ```sh
   ssh hive.home.arpa 'sudo truncate -s0 /etc/nixos/secrets/teleport/hive.token'
   ```

### Urbit

Urbit ships/fakes are stored under `~/workspace/urbit/` on hive:

- `taptev-donwyx` — main ship
- `zod` — local fakeship for testing
- `zod-backup-*` — backups

Urbit is run manually (not as a systemd service) via:

```sh
cd ~/workspace/urbit/taptev-donwyx
./urbit .
```

The web interface is exposed on port 8080 and proxied through skaia's nginx at
`https://urbit.valueof.info`.

**In config:**

- `hosts/hive/default.nix` — main configuration
- `hosts/hive/observability.nix` — metrics/logs streaming to skaia
- `hosts/skaia/observability.nix` — netdata parent + prometheus scrape for hive
- `hosts/skaia/nginx.nix` — urbit.valueof.info proxy to hive:8080

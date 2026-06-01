# Hive System Disk Replacement

Replace hive's system NVMe (e.g. predictive `smartd` wear warning)
while preserving data disks, the Urbit pier, and network identity.
Distinct from [Hive migration and bootstrap](../COLD-START.md#hive-migration-and-bootstrap)
(initial NixOS bring-up on existing hardware).

The procedure assumes the data layout we have: `/boot` + LUKS+LVM (root +
swap) on `nvme0n1`, with `/ssd` (Urbit pier), `/storage`, `/projects` on
separate SATA disks mounted by label. Because the data filesystems are
referenced by label, SATA port shuffling is safe.

**Pre-swap (hive still running):**

1. Capture SSH host keys + teleport node state from the live system:

   ```sh
   STAGE=/tmp/hive-recovery-stage
   sudo rm -rf "$STAGE"
   sudo mkdir -p "$STAGE"/{ssh,teleport,meta}
   sudo cp -a /etc/ssh/ssh_host_*_key /etc/ssh/ssh_host_*_key.pub \
     "$STAGE/ssh/"
   sudo cp -a /var/lib/teleport-node/. "$STAGE/teleport/"
   sudo cp /etc/machine-id "$STAGE/meta/machine-id"
   sudo blkid | sudo tee "$STAGE/meta/blkid.txt" >/dev/null
   sudo tar -czf /tmp/hive-recovery.tar.gz -C "$STAGE" .
   sudo chmod 0600 /tmp/hive-recovery.tar.gz
   sudo chown dlk:users /tmp/hive-recovery.tar.gz
   sudo rm -rf "$STAGE"
   ```

   Pull `/tmp/hive-recovery.tar.gz` off-host (e.g. `scp` to skaia and the
   workstation). Storing in two places matters — these contain hive's SSH
   host private keys and a valid teleport node identity.

1. Optional but recommended: `rsync` `/home/dlk/` to `/storage/dlk/` so user
   dotfiles + `.ssh/authorized_keys` survive. Exclude `.cache/` and
   `.local/share/Trash/`.

1. Stop urbit cleanly. The `urbit-taptev-donwyx` service uses SIGINT with
   `TimeoutStopSec=120`. Real-world urbit instances can take longer than
   that to flush; if `systemctl stop` reports `failed (timeout)` and the
   service was SIGKILL'd, the pier is *probably* fine but a quiescent
   snapshot is best taken from a `|exit`'d manual run if possible:

   ```sh
   sudo systemctl stop urbit-taptev-donwyx
   pgrep -af taptev-donwyx
   ```

1. Pier snapshot to **a different host** (e.g. skaia) for blast-radius
   isolation. ZFS-backed destination compresses well (~50%):

   ```sh
   # from skaia:
   rsync -aHAX --info=progress2,stats2 \
     dlk@hive.home.arpa:/ssd/urbit/taptev-donwyx/ \
     /home/dlk/hive-pier-snapshot-$(date +%F)/
   ```

   Compare apparent size + file count source vs dest to confirm:

   ```sh
   find /ssd/urbit/taptev-donwyx -type f | wc -l        # on hive
   du --apparent-size -sh /ssd/urbit/taptev-donwyx      # on hive
   ```

   This snapshot is for emergency restore only — restoring an out-of-date
   pier triggers identity breach.

1. Stage the flake on skaia for the installer to fetch later:

   ```sh
   # from workstation (cwd: nixos-config)
   git archive --format=tar.gz -o /tmp/nixos-config-flake.tar.gz HEAD
   scp /tmp/nixos-config-flake.tar.gz dlk@skaia:/home/dlk/iso/
   scp /tmp/hive-recovery.tar.gz       dlk@skaia:/home/dlk/iso/
   ```

1. `sudo poweroff`.

**Physical swap:**

- M.2 NVMe out (old), in (new).
- Leave all SATA disks alone. Hive's data filesystems mount by label, so
  port shuffling is safe — but unnecessary risk if you can avoid it.
- Boot from a current NixOS minimal installer USB.

**Install from USB (drive over SSH for ergonomics):**

1. SSH as `nixos@hive.home.arpa` from the workstation. The installer's
   `nixos` user has passwordless sudo.

1. Identify the new NVMe (`lsblk -d -o NAME,SIZE,VENDOR,MODEL`). Make
   absolutely sure you're targeting the new drive, not a data SATA disk.

1. Start a one-shot HTTP server on skaia (`cd /home/dlk/iso &&
   python3 -m http.server 8000`) and fetch the staged tarballs:

   ```sh
   cd /tmp
   curl -O http://skaia.home.arpa:8000/nixos-config-flake.tar.gz
   curl -O http://skaia.home.arpa:8000/hive-recovery.tar.gz
   ```

1. Partition, preserving the existing 3-partition layout. The vestigial
   1MiB `p1` keeps `nvme0n1p3` as the LUKS device path, matching the
   declared `boot.initrd.luks.devices.root.device`:

   ```sh
   DISK=/dev/nvme0n1
   sudo wipefs -a $DISK
   sudo sgdisk --zap-all $DISK
   sudo sgdisk \
     -n 1:1MiB:+1MiB    -t 1:8300 -c 1:"pad" \
     -n 2:0:+1GiB       -t 2:EF00 -c 2:"ESP" \
     -n 3:0:0           -t 3:8309 -c 3:"LUKS" \
     $DISK
   sudo partprobe $DISK
   ```

1. LUKS + LVM, recreating the existing UUIDs so
   `hosts/hive/hardware-configuration.nix` works unchanged:

   ```sh
   sudo cryptsetup luksFormat /dev/nvme0n1p3
   sudo cryptsetup luksOpen   /dev/nvme0n1p3 root
   sudo pvcreate /dev/mapper/root
   sudo vgcreate vg /dev/mapper/root
   sudo lvcreate -L 8G       -n swap vg
   sudo lvcreate -l 100%FREE -n root vg

   sudo mkfs.vfat -i 8619132C -n EFI                                /dev/nvme0n1p2
   sudo mkfs.ext4 -F -L root -U 9c37b50e-6323-4e07-b2d1-36fe8a4d2bb9 /dev/mapper/vg-root
   sudo mkswap     -L swap -U eda6fb00-9a24-4fe3-8c83-4d8fd4d7dd2b   /dev/mapper/vg-swap
   ```

1. Mount, stage flake, install — pointing at the harmonia LAN cache so the
   install completes in 1-2 minutes instead of pulling everything from
   cache.nixos.org:

   ```sh
   sudo mount /dev/mapper/vg-root /mnt
   sudo mkdir -p /mnt/boot
   sudo mount /dev/nvme0n1p2 /mnt/boot
   sudo mkdir -p /mnt/etc/nixos
   sudo tar -xzf /tmp/nixos-config-flake.tar.gz -C /mnt/etc/nixos
   sudo chown -R root:root /mnt/etc/nixos

   TRUSTKEY=$(tr -d "\n" < /mnt/etc/nixos/assets/harmonia-cache-public-key.txt)
   sudo nixos-install \
     --no-root-passwd \
     --flake /mnt/etc/nixos#hive \
     --option extra-substituters       "http://cache.home.arpa" \
     --option extra-trusted-public-keys "$TRUSTKEY"
   ```

1. Restore identity to the new root before reboot. `--no-root-passwd`
   intentionally leaves root locked; `sudo` is the only privilege path.

   ```sh
   mkdir -p /tmp/recovery
   tar -xzf /tmp/hive-recovery.tar.gz -C /tmp/recovery

   sudo cp /tmp/recovery/ssh/ssh_host_*_key     /mnt/etc/ssh/
   sudo cp /tmp/recovery/ssh/ssh_host_*_key.pub /mnt/etc/ssh/
   sudo chmod 600 /mnt/etc/ssh/ssh_host_*_key
   sudo chmod 644 /mnt/etc/ssh/ssh_host_*_key.pub
   sudo chown root:root /mnt/etc/ssh/ssh_host_*

   sudo mkdir -p /mnt/var/lib/teleport-node
   sudo cp -a /tmp/recovery/teleport/. /mnt/var/lib/teleport-node/
   sudo chown -R root:root /mnt/var/lib/teleport-node
   sudo chmod 750 /mnt/var/lib/teleport-node

   sudo cp /tmp/recovery/meta/machine-id /mnt/etc/machine-id
   ```

1. Restore `~/.ssh/authorized_keys` from the `/storage` home backup so SSH
   key auth works on first boot (`PasswordAuthentication=false` in
   `sshd_config`). Verify dlk's old uid:gid was 1000:100 — if so, the
   ownership matches what NixOS will assign to the new dlk on activation:

   ```sh
   sudo mkdir -p /tmp/storage
   sudo mount -o ro /dev/disk/by-label/STORAGE /tmp/storage
   sudo cp -a /tmp/storage/dlk/home-backup-*/.ssh /mnt/home/dlk/.ssh
   sudo chown -R 1000:100 /mnt/home/dlk
   sudo chmod 700 /mnt/home/dlk/.ssh
   sudo chmod 600 /mnt/home/dlk/.ssh/authorized_keys
   sudo umount /tmp/storage
   ```

1. **Set dlk's initial password while still in the installer.** This is
   the one step that, if skipped, results in a fresh hive where `sudo`
   cannot work because dlk has no password and root is locked. `chroot`
   into the new root via `nixos-enter` for a clean PAM context:

   ```sh
   sudo nixos-enter --root /mnt -- bash -c 'passwd dlk'
   ```

1. Tear down and reboot:

   ```sh
   sudo umount -R /mnt
   sudo vgchange -an vg
   sudo cryptsetup luksClose root
   sudo reboot
   ```

**Post-boot verification:**

1. LUKS unlocks at the local console with the existing passphrase.

1. SSH from the workstation — host key fingerprint should match the
   restored ed25519 (you may need to `ssh-keygen -R hive.home.arpa` to
   clear stale `known_hosts` entries from the installer phase).

1. Run the verification trio:

   ```sh
   ssh hive.home.arpa '
     findmnt --real -o TARGET,SOURCE,FSTYPE,LABEL,SIZE,USED
     systemctl is-active teleport-node smartd urbit-taptev-donwyx sshd
     smartctl -A -H /dev/nvme0 | sed -n "1,12p"
     sudo -v
   '
   tsh ls    # hive should be back with its labels (no re-enrollment)
   ```

1. Final structural check from the workstation:

   ```sh
   ssh hive.home.arpa 'sudo nixos-rebuild dry-activate --flake /etc/nixos#hive'
   ```

   If the resulting store path matches what `nixos-rebuild build
   --flake .#hive` produces locally, the running hive is byte-identical to
   `master`.

1. Restore user state from the `/storage` home backup as needed
   (`~/.gnupg`, `~/.ssh`, etc.). Drop any stale `~/.gnupg/gpg-agent.conf`
   that pins `pinentry-program` to a GC'd `/nix/store/...` path from the
   old system — `programs.gnupg.agent` (server-common) provides a system
   pinentry that `gpgconf` will find on its own.

**Cleanup after success:**

- Remove the recovery tarball from skaia's LAN-served dir (it contains SSH
  host private keys): `rm /home/dlk/iso/hive-recovery-*.tar.gz`.
- Keep the pier snapshot on skaia for ~1 week then drop it.
- Label and store (or recycle) the retired NVMe.

**Why the partition layout matches the old one exactly:**

`hosts/hive/hardware-configuration.nix` references three UUIDs (root, boot,
swap) and `hosts/hive/default.nix` references `/dev/nvme0n1p3` for LUKS. By
recreating filesystems with `mkfs.* -U <uuid>` / `mkfs.vfat -i <vol-id>` and
preserving the 3-partition layout, the flake works unchanged. The
alternative (regenerate `hardware-configuration.nix`) is also fine but adds
a config commit to the swap procedure.

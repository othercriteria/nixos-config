# Observability Stack

This document describes the observability setup for this NixOS system,
including metrics, logs, dashboards, storage, retention, backup, and disaster
recovery (DR).

All components run locally on the host. Metrics and logs are stored on a
ZFS-backed dataset for durability and easy backup.

## Prometheus Storage on ZFS

Prometheus data is stored in `/var/lib/prometheus2` by default. For
durability and easy backup, a dedicated ZFS dataset should be mounted at this
location. The dataset name (e.g., `fastdisk/prometheus`) must be set in the
host configuration for snapshot automation.

### Creating the ZFS Dataset and Mount

1. Create the ZFS dataset (replace `fastdisk` with your pool name):

   ```sh
   zfs create -o mountpoint=/var/lib/prometheus2 fastdisk/prometheus
   ```

1. Verify the dataset is mounted:

   ```sh
   zfs list
   ls -ld /var/lib/prometheus2
   ```

### ZFS Snapshots and Backups

Snapshots are taken automatically via a systemd timer. **Important:** The
dataset name (e.g., `fastdisk/prometheus`) must be set in the host config for
automation, and the dataset should be mounted at `/var/lib/prometheus2`.

```nix
services.prometheusZfsSnapshot.dataset = "fastdisk/prometheus";
```

#### Forcing a Manual Snapshot

To force a snapshot immediately:

```sh
sudo systemctl start prometheus-zfs-snapshot.service
```

#### Offsite Backup

Use ZFS send/receive to back up snapshots to another host or disk:

```sh
zfs send fastdisk/prometheus@snapshot | ssh backup-host zfs receive backupzpool/prometheus
```

## Metrics Retention

Prometheus is configured to retain metrics for 30 days (customizable).
Adjust with:

```nix
services.prometheus.extraFlags = [ "--storage.tsdb.retention.time=30d" ];
```

## Restore Procedure

To restore from a snapshot:

```sh
zfs rollback fastdisk/prometheus@desired-snapshot
```

Or receive from backup:

```sh
zfs receive -F fastdisk/prometheus < backupfile
```

## Grafana

Grafana dashboards are provisioned and can be managed as code.

## Loki and Promtail

Loki and Promtail collect and store logs on ZFS. Retention and backup are
managed via ZFS.

## Troubleshooting

For questions or issues, see the main project documentation or contact the
system maintainer.

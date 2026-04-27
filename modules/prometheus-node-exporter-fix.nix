# Workaround for a NixOS prometheus-node-exporter regression
#
# The NixOS exporter passes `--web.systemd-socket` to node_exporter, meaning
# the binary expects to receive its listening socket via systemd socket
# activation. However, the generated [Service] unit does NOT contain a
# `Sockets=prometheus-node-exporter.socket` directive, so when systemd
# restarts the service directly (which is what `nixos-rebuild switch` does
# for changed services) systemd does not pass any FDs along.
#
# The exporter then aborts with:
#
#     "no socket activation file descriptors found"
#
# After enough rapid restarts it hits systemd's default start-limit and
# stays down indefinitely. We hit this on skaia in April 2026 and lost
# ~4 days of node-level metrics before noticing.
#
# Adding the explicit `Sockets=` binding tells systemd to pass the listening
# FD to the service whether activation came via the socket unit or via a
# direct `systemctl restart`. Behaviour via socket activation is unchanged.
#
# Importing this module is harmless when the exporter is disabled: the fix
# is gated on `services.prometheus.exporters.node.enable`, which is the
# upstream option NixOS uses regardless of how the exporter was enabled
# (via `services.prometheus.exporters.node.enable = true`, our shared
# `custom.prometheus.nodeExporter.enable`, or anything else).
{ config, lib, ... }:

{
  config = lib.mkIf config.services.prometheus.exporters.node.enable {
    systemd.services.prometheus-node-exporter.serviceConfig.Sockets =
      "prometheus-node-exporter.socket";
  };
}

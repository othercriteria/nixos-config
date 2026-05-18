# Reusable systemd sandbox preset for small network-facing or compute-only
# services.
#
# This file does *not* declare any services itself. It is a function that
# returns a `serviceConfig`-shaped attrset of strict isolation defaults,
# intended to be `//`-merged with a service's own `User`, `ExecStart`, etc.
#
# Usage:
#
#   let
#     inherit (import ../../modules/hardened-service.nix { inherit lib; })
#       mkServiceConfig;
#   in {
#     systemd.services.my-service.serviceConfig = (mkServiceConfig {
#       readOnlyPaths = [ "/var/lib/my-service/data" ];
#       allowOutbound = false;
#     }) // {
#       User = "my-service";
#       Group = "my-service";
#       ExecStart = "...";
#     };
#   }
#
# Design intent:
# - Maximum reasonable strictness as the default. Consumers relax specific
#   knobs by overriding attributes after the `//` merge.
# - Aims to land around `systemd-analyze security <unit>` "OK" (<= 3.0) for a
#   simple Python/Go web app with no privileged needs.
# - No outbound network by default. Many small services bind to loopback and
#   are reached by nginx on the same host; they have no legitimate need to
#   make outbound connections, and forbidding them removes an attractive
#   post-exploit escape route.

{ lib }:

let
  inherit (lib) optionalAttrs;
in
{
  mkServiceConfig =
    {
      # Filesystem paths the service is allowed to read (in addition to the
      # nix store, which is always available). Use this for the service's
      # data directory.
      readOnlyPaths ? [ ]

    , # Filesystem paths the service is allowed to write. Empty means the
      # service can write nowhere persistent (PrivateTmp still gives it a
      # private /tmp).
      readWritePaths ? [ ]

    , # If true, the service may make outbound network connections. Default
      # false: only loopback is reachable.
      allowOutbound ? false

    , # Address families the service may use. The default permits IPv4, IPv6,
      # and AF_UNIX (the last is needed by some Python stdlib paths, journald,
      # and systemd notify sockets).
      addressFamilies ? [ "AF_INET" "AF_INET6" "AF_UNIX" ]

    , # IP allowlist used when allowOutbound is false. Listing "localhost"
      # permits accepting connections from 127.0.0.0/8 and ::1, which is what
      # we want for a service that binds to loopback and is fronted by nginx
      # on the same host.
      ipAddressAllow ? [ "localhost" ]

    , # Additional syscall filter entries appended to the default set.
      # Example: [ "@chown" ] if the service legitimately needs chown(2).
      systemCallFilterExtra ? [ ]

    , # Some interpreted languages (notably anything that JIT-compiles or
      # uses ctypes heavily) need writable+executable memory mappings. Set
      # this to false to relax MemoryDenyWriteExecute when needed; leave at
      # true for plain CPython without JIT extensions.
      memoryDenyWriteExecute ? true
    }:
    {
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      PrivateDevices = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectKernelLogs = true;
      ProtectControlGroups = true;
      ProtectClock = true;
      ProtectHostname = true;
      ProtectProc = "invisible";
      ProcSubset = "pid";
      ReadOnlyPaths = readOnlyPaths;
      ReadWritePaths = readWritePaths;

      NoNewPrivileges = true;
      CapabilityBoundingSet = "";
      AmbientCapabilities = "";
      RestrictSUIDSGID = true;
      RestrictRealtime = true;
      RestrictNamespaces = true;
      LockPersonality = true;
      MemoryDenyWriteExecute = memoryDenyWriteExecute;

      RestrictAddressFamilies = addressFamilies;

      SystemCallFilter = [
        "@system-service"
        "~@privileged"
        "~@resources"
      ] ++ systemCallFilterExtra;
      SystemCallArchitectures = "native";
    }
    // optionalAttrs (!allowOutbound) {
      IPAddressDeny = "any";
      IPAddressAllow = ipAddressAllow;
    };
}

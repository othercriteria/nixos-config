{ config, lib, pkgs, ... }:

let
  enableKubeconfig = config.services.k3s.enable or false;
  kubeconfigSource = "/etc/rancher/k3s/k3s.yaml";
  username = "dlk";
  serviceName = "populate-kubeconfig-for-${username}";
  script = ''
    set -euo pipefail
    export PATH="/run/current-system/sw/bin:$PATH"

    SRC="${kubeconfigSource}"
    if [ ! -f "$SRC" ]; then
      exit 0
    fi

    # Resolve home directory; prefer getent if available, otherwise shell expansion
    if command -v getent >/dev/null 2>&1; then
      HOME_DIR=$(getent passwd ${username} | cut -d: -f6)
    else
      HOME_DIR=$(eval echo ~${username})
    fi

    if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
      exit 0
    fi

    mkdir -p "$HOME_DIR/.kube"
    TMP="$(mktemp)"
    cp "$SRC" "$TMP"

    TARGET="$HOME_DIR/.kube/config"
    if [ -f "$TARGET" ] && ! cmp -s "$TMP" "$TARGET"; then
      ts="$(date +%Y%m%d-%H%M%S)"
      mv -f "$TARGET" "$TARGET.old-$ts"
    fi
    if [ ! -f "$TARGET" ] || ! cmp -s "$TMP" "$TARGET"; then
      install -m 0644 "$TMP" "$TARGET"
      chown ${username}:users "$TARGET" || chown ${username}:"$(id -gn ${username})" "$TARGET" || true
    fi
    rm -f "$TMP"
  '';

in
{
  config = lib.mkIf enableKubeconfig {
    systemd.services.${serviceName} = {
      description = "Populate ~/.kube/config for ${username} from local k3s kubeconfig";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      path = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.util-linux pkgs.glibc.bin ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      inherit script;
    };
  };
}

{ config, lib, pkgs, ... }:

let
  enableKubeconfig = config.services.k3s.enable or false;
  kubeconfigSource = "/etc/rancher/k3s/k3s.yaml";
  username = "dlk";
  serviceName = "populate-kubeconfig-for-${username}";
  hostName = config.networking.hostName or "";
  isMeteor = lib.hasPrefix "meteor-" hostName;
  meteorServerIp = "192.168.0.121";
  desiredContext = if isMeteor then "veil" else "skaia";
  script = ''
    set -euo pipefail
    export PATH="/run/current-system/sw/bin:$PATH"

    SRC="${kubeconfigSource}"
    if [ ! -f "$SRC" ]; then
      exit 0
    fi

    # Resolve home directory without relying solely on getent
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

    # For meteors, point server to the control-plane VIP and name context 'veil'
    if ${toString isMeteor}; then
      sed -i "s#server: https://127.0.0.1:6443#server: https://${meteorServerIp}:6443#" "$TMP" || true
    fi

    # Try to rename default context to desired name if kubectl is available
    if command -v kubectl >/dev/null 2>&1; then
      kubectl --kubeconfig "$TMP" config rename-context default "${desiredContext}" >/dev/null 2>&1 || true
    fi

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
      path = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.util-linux pkgs.glibc.bin pkgs.k3s ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      inherit script;
    };
  };
}

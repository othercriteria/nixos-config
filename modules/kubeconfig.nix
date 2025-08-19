{ config, lib, pkgs, ... }:

let
  enableKubeconfig = config.services.k3s.enable or false;
  kubeconfigSource = "/etc/rancher/k3s/k3s.yaml";
  username = "dlk";
  serviceName = "populate-kubeconfig-for-${username}";
  veilServerIp = "192.168.0.121";
  fallbackVeilFile = "/etc/nixos/assets/veil-kubeconfig";
  script = ''
    set -euo pipefail
    export PATH="/run/current-system/sw/bin:$PATH"

    SRC="${kubeconfigSource}"
    if [ ! -f "$SRC" ]; then
      exit 0
    fi

    # Resolve home directory
    if command -v getent >/dev/null 2>&1; then
      HOME_DIR=$(getent passwd ${username} | cut -d: -f6)
    else
      HOME_DIR=$(eval echo ~${username})
    fi

    if [ -z "$HOME_DIR" ] || [ ! -d "$HOME_DIR" ]; then
      exit 0
    fi

    mkdir -p "$HOME_DIR/.kube"

    TMP1="$(mktemp)"
    TMP2="$(mktemp)"
    OUTTMP="$(mktemp)"

    # skaia config
    cp "$SRC" "$TMP1"
    # Rename cluster and user names to avoid default collisions
    sed -i '/^clusters:/,/^users:/ s/^  name: default$/  name: skaia/' "$TMP1" || true
    sed -i '/^users:/,/^contexts:/ s/^  name: default$/  name: skaia/' "$TMP1" || true
    if command -v kubectl >/dev/null 2>&1; then
      kubectl --kubeconfig "$TMP1" config rename-context default skaia >/dev/null 2>&1 || true
      kubectl --kubeconfig "$TMP1" config set-context skaia --cluster=skaia --user=skaia >/dev/null 2>&1 || true
    fi

    HAVE_VEIL="0"
    # Try to fetch veil kubeconfig from meteor-1 via scp using FQDN, shortname, then IP
    if command -v scp >/dev/null 2>&1; then
      for H in meteor-1.veil.home.arpa meteor-1 ${veilServerIp}; do
        scp -q -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=accept-new \
          "$H:/etc/rancher/k3s/k3s.yaml" "$TMP2" 2>/dev/null && break || true
      done
    fi

    # Fallback to local file if scp didn't produce a file
    if [ ! -s "$TMP2" ] && [ -r "${fallbackVeilFile}" ]; then
      cp "${fallbackVeilFile}" "$TMP2"
    fi

    if [ -s "$TMP2" ]; then
      # Point to the control-plane IP, rename cluster/user and context to veil
      sed -i "s#server: https://127.0.0.1:6443#server: https://${veilServerIp}:6443#" "$TMP2" || true
      sed -i '/^clusters:/,/^users:/ s/^  name: default$/  name: veil/' "$TMP2" || true
      sed -i '/^users:/,/^contexts:/ s/^  name: default$/  name: veil/' "$TMP2" || true
      if command -v kubectl >/dev/null 2>&1; then
        kubectl --kubeconfig "$TMP2" config rename-context default veil >/dev/null 2>&1 || true
        kubectl --kubeconfig "$TMP2" config set-context veil --cluster=veil --user=veil >/dev/null 2>&1 || true
      fi
      HAVE_VEIL="1"
    fi

    TARGET="$HOME_DIR/.kube/config"
    if [ "$HAVE_VEIL" = "1" ] && command -v kubectl >/dev/null 2>&1; then
      KUBECONFIG="$TMP1:$TMP2" kubectl config view --flatten > "$OUTTMP"
      # Ensure skaia remains default
      kubectl --kubeconfig "$OUTTMP" config use-context skaia >/dev/null 2>&1 || true
    else
      cp "$TMP1" "$OUTTMP"
    fi

    if [ -f "$TARGET" ] && ! cmp -s "$OUTTMP" "$TARGET"; then
      ts="$(date +%Y%m%d-%H%M%S)"
      mv -f "$TARGET" "$TARGET.old-$ts"
    fi
    if [ ! -f "$TARGET" ] || ! cmp -s "$OUTTMP" "$TARGET"; then
      install -m 0644 "$OUTTMP" "$TARGET"
    fi

    rm -f "$TMP1" "$TMP2" "$OUTTMP"
  '';

in
{
  config = lib.mkIf enableKubeconfig {
    systemd.services.${serviceName} = {
      description = "Populate ~/.kube/config for ${username} (skaia + veil contexts)";
      wantedBy = [ "multi-user.target" ];
      wants = [ "network-online.target" ];
      after = [ "k3s.service" "network-online.target" ];
      path = [ pkgs.coreutils pkgs.gnugrep pkgs.gnused pkgs.util-linux pkgs.glibc.bin pkgs.k3s pkgs.openssh ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = username;
      };
      inherit script;
    };
  };
}

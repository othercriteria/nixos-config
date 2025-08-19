{ config, lib, pkgs, ... }:
{
  options.veil.kubeconfig = {
    enable = lib.mkEnableOption "Generate managed kubeconfig from k3s.yaml";

    clusterName = lib.mkOption {
      type = lib.types.str;
      default = "k3s";
      description = "Name to assign to the kubeconfig context for this host.";
    };

    serverAddress = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "If set, replace https://127.0.0.1:6443 with this address in the generated kubeconfig (e.g., https://192.168.0.121:6443).";
    };

    outputPath = lib.mkOption {
      type = lib.types.path;
      default = "/etc/kubernetes/kubeconfig";
      description = "Path to write the managed kubeconfig.";
    };
  };

  config = lib.mkIf config.veil.kubeconfig.enable {
    systemd.services.generate-kubeconfig = {
      description = "Generate managed kubeconfig from k3s.yaml";
      wantedBy = [ "multi-user.target" ];
      after = [ "k3s.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      path = [ pkgs.kubectl pkgs.coreutils pkgs.gnused ];
      script =
        let
          dest = config.veil.kubeconfig.outputPath;
          ctx = config.veil.kubeconfig.clusterName;
          server = config.veil.kubeconfig.serverAddress;
          sedReplace = lib.optionalString (server != null) ''
            sed -i "s#server: https://127.0.0.1:6443#server: ${server}#" "$tmp" || true
          '';
        in
        ''
          set -euo pipefail
          mkdir -p "$(dirname ${dest})"
          tmp=$(mktemp)
          cp /etc/rancher/k3s/k3s.yaml "$tmp"
          ${sedReplace}
          install -m 0644 "$tmp" "${dest}"
          rm -f "$tmp"
          # Rename default context to requested name and set as current
          KUBECONFIG="${dest}" kubectl config rename-context default "${ctx}" || true
          KUBECONFIG="${dest}" kubectl config use-context "${ctx}" || true
        '';
    };
  };
}

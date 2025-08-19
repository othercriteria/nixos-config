{ lib, pkgs, ... }:
{
  options = {
    veil.k3s.commonFlags = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "--disable traefik"
        ''--write-kubeconfig-mode "0644"''
        "--kubelet-arg=authentication-token-webhook=true"
        "--kubelet-arg=authorization-mode=Webhook"
        "--kube-controller-manager-arg=bind-address=0.0.0.0"
        "--kube-proxy-arg=metrics-bind-address=0.0.0.0"
        "--kube-scheduler-arg=bind-address=0.0.0.0"
        "--etcd-arg=listen-metrics-urls=http://0.0.0.0:2381"
        "--etcd-arg=metrics=extensive"
      ];
      description = "Common k3s flags shared by veil meteors.";
    };
  };

  config = {
    # DRY: default join token location for all meteors
    services.k3s.tokenFile = lib.mkDefault "/etc/nixos/secrets/veil-k3s-token";

    # Drain before k3s stops, uncordon after it starts (meteors)
    systemd.services.k3s = {
      path = [ pkgs.k3s pkgs.coreutils pkgs.util-linux ];
      preStop = ''
        set -e
        NODE="${toString (lib.mkDefault "${builtins.getEnv "HOSTNAME"}" )}"
        # Prefer configured hostName if available
        if [ -z "$NODE" ]; then NODE="${toString (builtins.getAttr "hostName" (builtins.tryEval { inherit (builtins) ; }.value) or "")}"; fi
        NODE="${toString config.networking.hostName}"
        # Drain this node before k3s stops; do not fail the stop if drain fails
        k3s kubectl drain "$NODE" \
          --ignore-daemonsets \
          --delete-emptydir-data \
          --force \
          --grace-period=60 \
          --timeout=10m || true
      '';
      postStart = ''
        NODE="${toString config.networking.hostName}"
        k3s kubectl uncordon "$NODE" || true
      '';
    };
  };
}

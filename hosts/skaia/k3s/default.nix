{ pkgs, ... }:

{
  imports = [
    ./gpu-operator.nix
    ./k3s-token.nix
    ./openebs-zfs-localpv.nix
    ./coredns-forward.nix
    ../../../modules/k3s-nvidia-runtime.nix
  ];

  environment.systemPackages = with pkgs; [
    k3s
    runc
  ];

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      # Provide etcd and other services
      "--cluster-init"

      # Security
      ''--write-kubeconfig-mode "0644"''
      "--kubelet-arg=authentication-token-webhook=true"
      "--kubelet-arg=authorization-mode=Webhook"

      # Metrics endpoints
      "--kube-controller-manager-arg=bind-address=0.0.0.0"
      "--kube-proxy-arg=metrics-bind-address=0.0.0.0"
      "--kube-scheduler-arg=bind-address=0.0.0.0"

      # Disable default local storage provider since we'll use ZFS-LocalPV
      "--disable local-storage"

      # Disable default ingress controller (Traefik) so we can use ingress-nginx instead
      "--disable traefik"

      # Guardrails against kubelet-managed ephemeral storage pressure. These do
      # not address ZFS snapshot growth on /var, but they help prevent
      # container log/image churn from triggering DiskPressure.
      "--kubelet-arg=container-log-max-size=25Mi"
      "--kubelet-arg=container-log-max-files=3"
      "--kubelet-arg=image-gc-high-threshold=85"
      "--kubelet-arg=image-gc-low-threshold=70"
      "--kubelet-arg=eviction-hard=nodefs.available<10%,imagefs.available<10%,nodefs.inodesFree<5%"
      "--kubelet-arg=eviction-minimum-reclaim=nodefs.available=1Gi,imagefs.available=1Gi"

      # TODO: replace these with more production-ready alternatives
      # "--disable servicelb"
    ];
  };

  systemd.services.k3s-ephemeral-prune = {
    description = "Prune stopped containers and unused images for k3s";
    serviceConfig = {
      Type = "oneshot";
    };
    path = [
      pkgs.k3s
      pkgs.coreutils
    ];
    script = ''
      set -euo pipefail
      echo "Pruning stopped containers..."
      # Do not pass -f. `crictl rm -a` removes stopped containers;
      # `-f` force-deletes running ones and their sandboxes. That
      # killed ib-gateway-live / decapod-live on 2026-08-15 (k3s
      # node stayed up; kubelet recreated pods and live 2FA fired).
      k3s crictl rm -a || true
      echo "Pruning unused images..."
      k3s crictl rmi --prune || true
    '';
  };

  systemd.timers.k3s-ephemeral-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}

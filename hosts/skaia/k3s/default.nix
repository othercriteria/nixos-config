{ config, pkgs, pkgs-stable, ... }:

{
  imports = [
    ./gpu-operator.nix
    ./k3s-token.nix
    ./openebs-zfs-localpv.nix
    ./coredns-forward.nix
  ];

  environment.systemPackages = with pkgs; [
    k3s
    runc
    # NOTE: Reverting to stable toolkit due to issues with unstable version (1.17.x+)
    # See summary below.
    pkgs-stable.nvidia-container-toolkit
  ];

  # Summary of issues encountered with unstable nvidia-container-toolkit (v1.17.x):
  # 1. Package structure changed: Runtime binaries moved to a `.tools` output.
  #    Required updating `containerdConfigTemplate` `BinaryName` to e.g.:
  #    `${pkgs.nvidia-container-toolkit.tools}/bin/nvidia-container-runtime.cdi`
  # 2. `.cdi` runtime caused glibc errors in GPU Operator pods (e.g. validator):
  #    `undefined symbol: __tunable_is_initialized`. This stems from incompatibility
  #    between the host (NixOS) glibc injected by the runtime and the glibc expected
  #    by the container images.
  # 3. `.legacy` runtime failed as it expected `ldconfig` at `/sbin/ldconfig`,
  #    which doesn't exist in NixOS, and Nixpkgs patches didn't cover this case.
  # Reverting to stable defers resolving these compatibility issues.

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

    containerdConfigTemplate = ''
      {{ template "base" . }}
      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
      privileged_without_host_devices = false
      runtime_engine = ""
      runtime_root = ""
      runtime_type = "io.containerd.runc.v2"

      [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
      BinaryName = "/run/current-system/sw/bin/nvidia-container-runtime"
      SystemdCgroup = false
    '';
  };

  systemd.services.k3s-ephemeral-prune = {
    description = "Prune stopped containers and unused images for k3s";
    serviceConfig = {
      Type = "oneshot";
    };
    path = [ pkgs.k3s pkgs.coreutils ];
    script = ''
      set -euo pipefail
      echo "Pruning stopped containers..."
      k3s crictl rm -fa || true
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

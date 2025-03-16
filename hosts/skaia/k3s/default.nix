{ config, pkgs, ... }:

{
  imports = [
    ./gpu-operator.nix
    ./k3s-token.nix
    ./openebs-zfs-localpv.nix
  ];

  environment.systemPackages = with pkgs; [
    k3s
    runc
    nvidia-container-toolkit
  ];

  hardware.nvidia-container-toolkit.enable = true;

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

      # TODO: replace these with more production-ready alternatives
      # "--disable servicelb"
      # "--disable traefik"
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
}

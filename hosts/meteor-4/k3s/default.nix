{ config, pkgs, pkgs-stable, lib, ... }:

{
  imports = [
    ../../../modules/veil/k3s-common.nix
  ];

  # nvidia-container-toolkit for GPU workloads
  # Using stable due to glibc compatibility issues with unstable v1.17.x+
  # (see hosts/skaia/k3s/default.nix for details)
  environment.systemPackages = [
    pkgs-stable.nvidia-container-toolkit
  ];

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString ([
      "--server https://192.168.0.121:6443" # API server on meteor-1
      "--node-label=gpu=true"
    ] ++ config.veil.k3s.commonFlags);

    # Register nvidia runtime with containerd
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

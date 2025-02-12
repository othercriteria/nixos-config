{ config, pkgs, ... }:

{
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
      ''--write-kubeconfig-mode "0644"''
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
          SystemdCgroup = true
    '';
  };
}

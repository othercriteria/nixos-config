# Host NVIDIA container runtime for k3s nodes that use the host driver.
#
# nixpkgs 1.17+ moved the runtimes to a `tools` output, and the default
# `nvidia-container-runtime` auto-selects jit-cdi. That CDI path injected
# host glibc into GPU Operator pods (`__tunable_is_initialized`).
# `nvidia-container-runtime.legacy` keeps the prestart hook those pods
# already use. nixpkgs rewrites `/sbin/ldconfig` to the store glibc; the
# CLI path still has to be set because the default is `/usr/bin`.
#
# Pods that set NVIDIA_DRIVER_CAPABILITIES=all (the GPU Operator device
# plugin and validator) make the legacy runtime glob for libcuda.so.*.*
# under FHS paths such as /usr/lib/x86_64-linux-gnu. NixOS publishes the
# driver at /run/opengl-driver, so that directory is linked there.
{
  pkgs,
  lib,
  ...
}:

{
  environment.systemPackages = [
    pkgs.nvidia-container-toolkit
  ];

  system.activationScripts.nvidia-driver-lib-path = {
    text = ''
      mkdir -p /usr/lib
      ln -sfn /run/opengl-driver/lib /usr/lib/x86_64-linux-gnu
    '';
    deps = [ ];
  };

  environment.etc."nvidia-container-runtime/config.toml".text = ''
    [nvidia-container-cli]
    ldconfig = "@${lib.getExe' pkgs.glibc "ldconfig"}"
    path = "${lib.getExe' pkgs.libnvidia-container "nvidia-container-cli"}"
    [nvidia-container-runtime-hook]
    path = "${lib.getOutput "tools" pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime-hook"
  '';

  services.k3s.containerdConfigTemplate = ''
    {{ template "base" . }}
    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia]
    privileged_without_host_devices = false
    runtime_engine = ""
    runtime_root = ""
    runtime_type = "io.containerd.runc.v2"

    [plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia.options]
    BinaryName = "${lib.getOutput "tools" pkgs.nvidia-container-toolkit}/bin/nvidia-container-runtime.legacy"
    SystemdCgroup = false
  '';
}

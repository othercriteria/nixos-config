{ config, pkgs, ... }:

{
  imports = [
    ./k3s-token.nix
    ./openebs-zfs-localpv.nix
  ];

  environment.systemPackages = with pkgs; [
    k3s
    runc
    nvidia-container-toolkit
  ];

  hardware.nvidia-container-toolkit.enable = true;

  # GPU Operator expects nvidia-smi to be in (/host/)/usr/bin, and to
  # not crash even when it's called with old library versions that
  # don't match the version of the driver. :thinking:
  #
  # Additionally, modify clusterpolicy/cluster-policy, setting:
  #   validator:
  #     driver:
  #       env:
  #       - name: DISABLE_DEV_CHAR_SYMLINK_CREATION
  #         value: "true"
  system.activationScripts = {
    nvidia-smi-wrapper = {
      text = ''
        # Create directories
        mkdir -p /run/nvidia-smi-dummy /usr/bin

        # Create dummy script
        cat > /run/nvidia-smi-dummy/nvidia-smi << 'EOF'
        #!/bin/sh
        echo "GPU Operator Validator Dummy"
        exit 0
        EOF
        chmod +x /run/nvidia-smi-dummy/nvidia-smi

        # Remove any existing symlink or file
        rm -f /usr/bin/nvidia-smi

        # Create symlink to dummy script for GPU Operator
        ln -sf /run/nvidia-smi-dummy/nvidia-smi /usr/bin/nvidia-smi
      '';
      deps = [ ];
    };
  };

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

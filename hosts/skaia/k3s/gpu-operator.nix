{ config, pkgs, ... }:

{
  systemd.services.gpu-operator-setup = {
    description = "Deploy GPU Operator and apply Kyverno patch";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" "network.target" "network-online.target" ];
    requires = [ "k3s.service" "network.target" "network-online.target" ];
    path = [ pkgs.k3s pkgs.kubernetes-helm ];
    environment = {
      KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    };
    script = ''
      echo "Deploying GPU Operator..."

      # Wait for k3s API to be responsive
      echo "Waiting for k3s API to be available..."
      until k3s kubectl get --raw "/healthz" &>/dev/null; do
        sleep 5
      done

      # Install GPU Operator with Helm
      helm repo add nvidia https://helm.ngc.nvidia.com/nvidia
      helm repo update
      helm upgrade gpu-operator \
        --install \
        --namespace gpu-operator \
        --create-namespace \
        nvidia/gpu-operator \
        --set driver.enabled=false \
        --set toolkit.enabled=false \
        --set validator.driver.env[0].name=DISABLE_DEV_CHAR_SYMLINK_CREATION \
        --set-string validator.driver.env[0].value="true" \
        --set validator.env[0].name=NVIDIA_DRIVER_CAPABILITIES \
        --set validator.env[0].value=all \
        --set validator.env[1].name=NVIDIA_VISIBLE_DEVICES \
        --set validator.env[1].value=all \
        --set validator.env[2].name=NVIDIA_DISABLE_REQUIRE \
        --set-string validator.env[2].value="true"

      echo "Applying Kyverno patch for GPU Operator..."
      k3s kubectl apply -f /etc/nixos/assets/kyverno-patch-gpu-validator.yaml
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30";
    };
  };

  # GPU Operator expects nvidia-smi to be in (/host/)/usr/bin, and to
  # not crash even when it's called with old library versions that
  # don't match the version of the driver. :thinking:
  #
  # Keeping this (rather than patching out entirely) since this will
  # still check that pods can see the host system.
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
}

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
      set -euo pipefail

      echo "Deploying GPU Operator..."

      # Wait for k3s API to be responsive
      echo "Waiting for k3s API to be available..."
      until k3s kubectl get --raw "/healthz" &>/dev/null; do
        sleep 5
      done
      if ! helm repo add nvidia https://helm.ngc.nvidia.com/nvidia >/dev/null 2>&1; then
        echo "Updating existing Helm repo nvidia..."
        helm repo update nvidia
      fi

      status_file=$(mktemp)
      if helm -n gpu-operator status gpu-operator >"$status_file" 2>&1 && grep -q "^STATUS: pending" "$status_file"; then
        status_line=$(grep "^STATUS:" "$status_file")
        echo "Helm release gpu-operator is stuck ($status_line). Attempting rollback..."
        if ! helm -n gpu-operator rollback gpu-operator --cleanup-on-fail; then
          echo "Rollback failed, uninstalling release..."
          helm -n gpu-operator uninstall gpu-operator || true
        fi
      fi
      rm -f "$status_file"

      # TODO: Re-enable CDI once /run/nvidia/driver contains the host GPU driver
      # artifacts (or we point the chart at /run/opengl-driver). For v25.10.0 CDI
      # became mandatory by default, but we currently rely on the host-installed
      # driver with no files under /run/nvidia/driver, so the device plugin fails
      # to build CDI specs. See 2025-11-19 notes.
      #
      # TODO: Revert dcgmExporter back to the distroless image when CDI is wired
      # up and dcgm-exporter stops crashing; we use the Ubuntu image only for
      # easier debugging (kubectl exec, extra tooling, etc.).
      helm upgrade gpu-operator \
        --install \
        --atomic \
        --cleanup-on-fail \
        --wait \
        --timeout 15m \
        --namespace gpu-operator \
        --create-namespace \
        nvidia/gpu-operator \
        --set cdi.enabled=false \
        --set dcgmExporter.version=4.4.1-4.6.0-ubuntu22.04 \
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

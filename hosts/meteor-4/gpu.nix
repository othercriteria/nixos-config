{ config, pkgs, ... }:

{
  # Load NVIDIA proprietary driver (blocks nouveau)
  services.xserver.videoDrivers = [ "nvidia" ];

  hardware = {
    graphics.enable = true;

    nvidia = {
      # Use the production driver
      package = config.boot.kernelPackages.nvidiaPackages.production;

      # Headless: no power management needed
      powerManagement.enable = false;

      # Required for some features
      modesetting.enable = true;

      # Keep GPU initialized for container workloads
      nvidiaPersistenced = true;

      # Use proprietary driver (not the open kernel modules)
      open = false;

      # No desktop, no need for nvidia-settings GUI
      nvidiaSettings = false;
    };

    # Enable container toolkit for k3s GPU workloads
    nvidia-container-toolkit.enable = true;
  };

  # Ensure nvidia-smi is available for debugging
  environment.systemPackages = [ config.hardware.nvidia.package ];
}

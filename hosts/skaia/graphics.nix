{ config, pkgs, ... }:

{
  hardware = {
    # Enable NVIDIA container toolkit for Docker GPU access
    # This generates CDI specs at boot, allowing --gpus flag to work
    nvidia-container-toolkit.enable = true;

    graphics = {
      enable = true;
      enable32Bit = true;
      extraPackages = with pkgs; [
        nvidia-vaapi-driver
        libva-vdpau-driver
        libvdpau
      ];
    };
    nvidia = {
      powerManagement = {
        enable = false;
        finegrained = false;
      };

      modesetting.enable = true;

      # nvidiaPersistenced = true;

      forceFullCompositionPipeline = true;

      open = false;

      # Exposed via `nvidia-settings`.
      nvidiaSettings = true;

      package = config.boot.kernelPackages.nvidiaPackages.latest;
    };
  };
}

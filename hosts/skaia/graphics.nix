{ config, pkgs, ... }:

{
  hardware = {
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

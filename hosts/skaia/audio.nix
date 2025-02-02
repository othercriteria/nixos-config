{ config, ... }:

{
  hardware.bluetooth = {
    enable = true;
    powerOnBoot = true;
  };

  services = {
    pipewire = {
      enable = true;
      alsa.enable = true;
      alsa.support32Bit = true;
      pulse.enable = true;
      # If you want to use JACK applications, uncomment this
      #jack.enable = true;

      # Enable Bluetooth audio support
      wireplumber.enable = true;
    };

    # Enable Bluetooth service
    blueman.enable = true;
  };
}

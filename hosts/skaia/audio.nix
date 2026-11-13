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
      # jack.enable puts PipeWire's libjack on the session
      # LD_LIBRARY_PATH, and that option is now deprecated. A JACK
      # client can be launched with pw-jack from pkgs.pipewire.jack.

      # Enable Bluetooth audio support
      wireplumber.enable = true;
    };

    # Enable Bluetooth service
    blueman.enable = true;
  };
}

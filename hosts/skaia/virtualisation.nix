{ config, ... }:

{
  virtualisation = {
    # podman = {
    #   enable = true;
    #
    #   dockerCompat = true;
    #   defaultNetwork.settings.dns_enabled = true;
    # };

    docker = {
      enable = true;
      daemon.settings = {
        default-ulimits = {
          nofile = {
            name = "nofile";
            hard = 64000;
            soft = 64000;
          };
        };
      };
    };

    containerd.enable = true;

    virtualbox.host = {
      enable = true;
      enableExtensionPack = true;
    };
  };
}

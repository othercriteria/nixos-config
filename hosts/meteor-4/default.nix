{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ./gpu.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-4";
    hostId = "21c8b855";
  };

  custom.teleportNode = {
    enable = true;
    tokenFile = "/etc/nixos/secrets/teleport/meteor-4.token"; # COLD START: populate with join token from skaia
    labels = {
      role = "k3s-server";
      site = "residence-1";
      gpu = "true";
    };
  };
}

{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-2";
    hostId = "63643165"; # COLD START: set a unique hostId after install
  };

  custom.teleportNode = {
    enable = true;
    tokenFile = "/etc/nixos/secrets/teleport/meteor-2.token"; # COLD START: populate with join token from skaia
    labels = {
      role = "k3s-server";
      site = "residence-1";
    };
  };
}

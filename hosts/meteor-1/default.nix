{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-1";
    hostId = "36613562"; # COLD START: set a unique hostId after install
  };

  # COLD START: Initialize this node first with --cluster-init

  custom.teleportNode = {
    enable = true;
    tokenFile = "/etc/nixos/secrets/teleport/meteor-1.token"; # COLD START: populate with join token from skaia
    labels = {
      role = "k3s-server";
      site = "residence-1";
    };
  };
}

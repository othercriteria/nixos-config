{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ./firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-1";
    hostId = "00000001"; # COLD START: set a unique hostId after install
  };

  # COLD START: Initialize this node first with --cluster-init
}

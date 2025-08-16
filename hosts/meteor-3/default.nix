{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ./firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-3";
    hostId = "00000003"; # COLD START: set a unique hostId after install
  };
}

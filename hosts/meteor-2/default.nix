{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ./firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-2";
    hostId = "00000002"; # COLD START: set a unique hostId after install
  };
}

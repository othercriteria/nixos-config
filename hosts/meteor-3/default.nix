{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-3";
    hostId = "37363365"; # COLD START: set a unique hostId after install
  };
}

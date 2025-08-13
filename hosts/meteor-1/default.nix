{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./firewall.nix
    ./k3s
  ] ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking = {
    hostName = "meteor-1";
    hostId = "00000001"; # COLD START: set a unique hostId after install
  };

  # COLD START: Initialize this node first with --cluster-init
}

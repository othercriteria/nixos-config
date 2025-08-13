{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./firewall.nix
    ./k3s
  ] ++ lib.optional (builtins.pathExists ./hardware-configuration.nix) ./hardware-configuration.nix;

  networking = {
    hostName = "meteor-3";
    hostId = "00000003"; # COLD START: set a unique hostId after install
  };
}

{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ../../modules/veil/kubeconfig.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-1";
    hostId = "36613562"; # COLD START: set a unique hostId after install
  };

  # COLD START: Initialize this node first with --cluster-init
}

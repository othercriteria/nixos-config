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

  veil.kubeconfig = {
    enable = true;
    clusterName = "veil";
    serverAddress = "https://192.168.0.121:6443";
    outputPath = "/etc/kubernetes/kubeconfig";
  };

  environment.sessionVariables.KUBECONFIG = "/etc/kubernetes/kubeconfig";

  # COLD START: Initialize this node first with --cluster-init
}

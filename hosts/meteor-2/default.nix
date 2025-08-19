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
    hostName = "meteor-2";
    hostId = "63643165"; # COLD START: set a unique hostId after install
  };

  veil.kubeconfig = {
    enable = true;
    clusterName = "veil";
    serverAddress = "https://192.168.0.122:6443";
    outputPath = "/etc/kubernetes/kubeconfig";
  };

  environment.sessionVariables.KUBECONFIG = "/etc/kubernetes/kubeconfig";
}

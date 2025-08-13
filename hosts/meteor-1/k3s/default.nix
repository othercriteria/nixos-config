{ config, pkgs, lib, ... }:

{
  imports = [ ./join-token.nix ];

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString [
      "--cluster-name veil"
      "--cluster-init" # COLD START: run meteor-1 first
      "--disable traefik"
      ''--write-kubeconfig-mode "0644"''
      "--kubelet-arg=authentication-token-webhook=true"
      "--kubelet-arg=authorization-mode=Webhook"
      "--kube-controller-manager-arg=bind-address=0.0.0.0"
      "--kube-proxy-arg=metrics-bind-address=0.0.0.0"
      "--kube-scheduler-arg=bind-address=0.0.0.0"
    ];
  };
}

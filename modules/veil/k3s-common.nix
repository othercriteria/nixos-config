{ lib, ... }:
{
  options.veil.k3s.commonFlags = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [
      "--disable traefik"
      ''--write-kubeconfig-mode "0644"''
      "--kubelet-arg=authentication-token-webhook=true"
      "--kubelet-arg=authorization-mode=Webhook"
      "--kube-controller-manager-arg=bind-address=0.0.0.0"
      "--kube-proxy-arg=metrics-bind-address=0.0.0.0"
      "--kube-scheduler-arg=bind-address=0.0.0.0"
      "--etcd-arg=listen-metrics-urls=http://0.0.0.0:2381"
    ];
    description = "Common k3s flags shared by veil meteors.";
  };

  # DRY: default join token location for all meteors
  services.k3s.tokenFile = lib.mkDefault "/etc/nixos/secrets/veil-k3s-token";
}

{ config, pkgs, ... }:

{
  systemd.services.kube-state-metrics = {
    description = "Deploy kube-state-metrics after k3s";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" ];
    path = [ pkgs.k3s ];
    script = ''
      echo "Deploying kube-state-metrics..."
      k3s kubectl apply -f /etc/nixos/assets/kube-state-metrics.yaml
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}

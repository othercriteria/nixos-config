{ config, pkgs, ... }:

{
  # Configure CoreDNS to forward veil/home.arpa to Unbound on skaia
  # Uses the coredns-custom ConfigMap which k3s natively imports via:
  #   import /etc/coredns/custom/*.server
  # This is more robust than patching the main Corefile directly.
  systemd.services.k3s-coredns-forward = {
    description = "Configure CoreDNS forwards for veil/home.arpa";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" "network.target" "network-online.target" ];
    requires = [ "k3s.service" "network.target" "network-online.target" ];
    path = [ pkgs.k3s pkgs.coreutils ];
    environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30";
    };
    script = ''
      set -euo pipefail

      echo "Waiting for CoreDNS deployment to be ready..."
      until k3s kubectl -n kube-system get deployment coredns >/dev/null 2>&1; do
        sleep 3
      done

      echo "Applying coredns-custom ConfigMap..."
      k3s kubectl apply -f - <<'EOF'
      apiVersion: v1
      kind: ConfigMap
      metadata:
        name: coredns-custom
        namespace: kube-system
      data:
        # Keys must end with .server for custom server blocks
        # These are imported via: import /etc/coredns/custom/*.server
        home-arpa.server: |
          veil.home.arpa:53 {
              errors
              cache 30
              forward . 192.168.0.160
          }

          home.arpa:53 {
              errors
              cache 30
              forward . 192.168.0.160
          }
      EOF

      # Restart CoreDNS to pick up the new custom config
      echo "Restarting CoreDNS..."
      k3s kubectl -n kube-system rollout restart deployment coredns
      k3s kubectl -n kube-system rollout status deployment coredns --timeout=60s

      echo "CoreDNS custom forwards configured successfully."
    '';
  };
}

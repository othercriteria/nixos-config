{ config, pkgs, ... }:

{
  # Patch CoreDNS on the local k3s to forward veil/home.arpa to Unbound on skaia
  systemd.services.k3s-coredns-forward = {
    description = "Configure CoreDNS forwards for veil/home.arpa";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" "network.target" "network-online.target" ];
    requires = [ "k3s.service" "network.target" "network-online.target" ];
    path = [ pkgs.k3s pkgs.coreutils pkgs.gnugrep ];
    environment.KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30";
    };
    script = ''
            set -euo pipefail

            echo "Waiting for CoreDNS ConfigMap..."
            until k3s kubectl -n kube-system get configmap coredns >/dev/null 2>&1; do
              sleep 3
            done

            CURRENT_COREFILE=$(k3s kubectl -n kube-system get configmap coredns -o jsonpath='{.data.Corefile}')

            # If already configured, exit early
            if echo "$CURRENT_COREFILE" | grep -q "veil.home.arpa"; then
              echo "CoreDNS already forwards veil/home.arpa; nothing to do."
              exit 0
            fi

            TMP_COREFILE=$(mktemp)
            cat > "$TMP_COREFILE" <<'EOF'
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
            # Append existing Corefile
            printf "%s\n" "$CURRENT_COREFILE" >> "$TMP_COREFILE"

            # Apply updated ConfigMap
            k3s kubectl -n kube-system create configmap coredns \
              --from-file=Corefile="$TMP_COREFILE" \
              -o yaml --dry-run=client | \
              k3s kubectl apply -f -

            # Restart CoreDNS
            k3s kubectl -n kube-system rollout restart deployment coredns
    '';
  };
}

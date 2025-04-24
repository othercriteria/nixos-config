{ config, pkgs, ... }:

{
  systemd.services.k3s-token-for-prometheus = {
    description = "Create k3s token file for Prometheus";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" ];
    path = [ pkgs.k3s pkgs.coreutils ];
    script = ''
      # COLD START: k3s must be running for the Prometheus client credentials extraction service to succeed. See docs/COLD-START.md for details.
      echo "Starting k3s token extraction..."

      # Wait for k3s to be ready
      echo "Waiting for k3s to be ready..."
      ATTEMPTS=0
      until k3s kubectl get nodes &>/dev/null; do
        ATTEMPTS=$((ATTEMPTS + 1))
        if [ $ATTEMPTS -gt 12 ]; then
          echo "Timeout waiting for k3s after 60 seconds"
          exit 1
        fi
        echo "k3s not ready, waiting 5 seconds... (attempt $ATTEMPTS)"
        sleep 5
      done

      echo "k3s is ready, proceeding with token extraction"

      # Create directory
      mkdir -p /var/lib/prometheus-k3s

      # Extract client certificate and key from k3s config
      echo "Extracting k3s credentials..."
      k3s kubectl config view --raw -o jsonpath='{.users[0].user.client-certificate-data}' | base64 -d > /var/lib/prometheus-k3s/client.crt
      k3s kubectl config view --raw -o jsonpath='{.users[0].user.client-key-data}' | base64 -d > /var/lib/prometheus-k3s/client.key

      echo "Setting permissions..."
      chown -R prometheus:prometheus /var/lib/prometheus-k3s
      chmod 640 /var/lib/prometheus-k3s/client.{crt,key}

      echo "Credential extraction completed successfully"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}

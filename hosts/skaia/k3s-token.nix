{ config, pkgs, ... }:

{
  systemd.services.k3s-token-for-prometheus = {
    description = "Create k3s token file for Prometheus";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" ];
    path = [ pkgs.k3s ];
    script = ''
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

      # Create a service account for Prometheus if it doesn't exist
      if ! k3s kubectl get serviceaccount prometheus -n kube-system &>/dev/null; then
        echo "Creating prometheus service account..."
        k3s kubectl create serviceaccount prometheus -n kube-system
      fi

      # Create ClusterRole if it doesn't exist
      if ! k3s kubectl get clusterrole prometheus-k8s &>/dev/null; then
        echo "Creating prometheus cluster role..."
        k3s kubectl create clusterrole prometheus-k8s --verb=get,list,watch \
          --resource=nodes,nodes/metrics,services,endpoints,pods,namespaces,serviceaccounts
      fi

      # Create ClusterRoleBinding if it doesn't exist
      if ! k3s kubectl get clusterrolebinding prometheus-k8s &>/dev/null; then
        echo "Creating prometheus cluster role binding..."
        k3s kubectl create clusterrolebinding prometheus-k8s \
          --clusterrole=prometheus-k8s \
          --serviceaccount=kube-system:prometheus
      fi

      # Create token secret if it doesn't exist
      if ! k3s kubectl -n kube-system get secret prometheus-token &>/dev/null; then
        echo "Creating new token secret..."
        k3s kubectl -n kube-system create token prometheus > /var/lib/prometheus-k3s/k3s.token
      fi

      echo "Setting permissions..."
      chown -R prometheus:prometheus /var/lib/prometheus-k3s
      chmod 640 /var/lib/prometheus-k3s/k3s.token

      echo "Token extraction completed successfully"
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
  };
}

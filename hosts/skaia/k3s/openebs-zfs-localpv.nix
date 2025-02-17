{ config, pkgs, ... }:

{
  # https://github.com/longhorn/longhorn/issues/2166
  systemd.tmpfiles.rules = [
    "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
  ];

  # Create systemd service to deploy OpenEBS ZFS-LocalPV
  systemd.services.openebs-zfs-setup = {
    description = "Deploy OpenEBS ZFS-LocalPV";
    wantedBy = [ "multi-user.target" ];
    after = [ "k3s.service" "network.target" "network-online.target" ];
    requires = [ "k3s.service" "network.target" "network-online.target" ];
    path = [ pkgs.k3s pkgs.kubernetes-helm ];
    environment = {
      KUBECONFIG = "/etc/rancher/k3s/k3s.yaml";
    };
    script = ''
      echo "Deploying OpenEBS ZFS-LocalPV..."

      # Wait for k3s API to be responsive
      echo "Waiting for k3s API to be available..."
      until k3s kubectl get --raw "/healthz" &>/dev/null; do
        sleep 5
      done

      # Label the node
      k3s kubectl label node skaia openebs.io/nodeid=skaia --overwrite

      # Install OpenEBS
      helm repo add openebs https://openebs.github.io/openebs
      helm repo update
      helm upgrade openebs \
        --namespace openebs \
        --create-namespace \
        openebs/openebs \
        --set engines.replicated.mayastor.enabled=false

      # Wait for ZFS controller to be ready
      echo "Waiting for ZFS controller to be ready..."
      until k3s kubectl get pods -n openebs -l app=openebs-zfs-controller -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -q "true true true true true"; do
        echo "Waiting for ZFS controller pods..."
        sleep 5
      done

      # Wait for ZFS node to be ready
      echo "Waiting for ZFS node to be ready..."
      until k3s kubectl get pods -n openebs -l name=openebs-zfs-node -o jsonpath='{.items[*].status.containerStatuses[*].ready}' | grep -q "true true"; do
        echo "Waiting for ZFS node pods..."
        sleep 5
      done

      # Create StorageClass for slowdisk
      cat <<EOF | k3s kubectl apply -f -
      apiVersion: storage.k8s.io/v1
      kind: StorageClass
      metadata:
        name: openebs-zfs-slowdisk
      provisioner: zfs.csi.openebs.io
      parameters:
        poolname: "slowdisk"
        fstype: "zfs"
        recordsize: "128k"
        compression: "on"
        dedup: "off"
      allowVolumeExpansion: true
      EOF
    '';
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = "30";
    };
  };
}

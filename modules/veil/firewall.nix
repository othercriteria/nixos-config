{ config, lib, ... }:

{
  networking.firewall = {
    allowedTCPPorts = [
      22
      6443 # k3s API
      2379
      2380 # etcd peer/API
      2381 # etcd metrics
      10249 # kube-proxy metrics
      10250 # kubelet metrics
      10257 # kube-controller-manager metrics (https)
      10259 # kube-scheduler metrics (https)
      9100 # node-exporter metrics
    ];
    allowedUDPPorts = [
      8472 # flannel VXLAN
    ];
    allowPing = true;
  };
}

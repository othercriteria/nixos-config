{ config, lib, ... }:

{
  networking.firewall = {
    allowedTCPPorts = [
      22
      6443 # k3s API
      2379
      2380 # etcd peer/API
      10250 # kubelet metrics
      9100 # node-exporter metrics
    ];
    allowedUDPPorts = [
      8472 # flannel VXLAN
    ];
    allowPing = true;
  };
}

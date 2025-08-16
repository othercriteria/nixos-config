{ config, ... }:

{
  networking.firewall = {
    allowedTCPPorts = [
      22
      80
      139
      443
      445
      6443 # k3s: required so pods can reach API server
      6881 # Bittorrent
      8200
      9999
      10250 # kubelet metrics
      30400 # NVIDIA DCGM Exporter
      53 # DNS (unbound)
    ];
    allowedUDPPorts = [
      137
      138
      1900
      6881 # Bittorrent
      7881 # KTorrent: DHT
      8881 # KTorrent
      53 # DNS (unbound)
    ];
    # TODO: narrow the range of allowed UDP ports
    allowedUDPPortRanges = [{ from = 13337; to = 65535; }];
    allowPing = true;
  };
}

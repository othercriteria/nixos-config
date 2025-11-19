{ config, ... }:

{
  networking.firewall = {
    allowedTCPPorts = [
      22 # SSH (public WAN forward today)
      53 # DNS resolver (Unbound; LAN + k3s overlays only)
      80 # HTTP (nginx + ACME challenges)
      139 # Samba NetBIOS session (should remain LAN-only)
      443 # HTTPS (reverse proxy entrypoint)
      445 # Samba SMB over TCP (LAN-only expectation)
      3023 # Teleport proxy (SSH/RDP/WebApp entrypoint)
      3024 # Teleport reverse tunnel listener
      3026 # Teleport Kubernetes proxy listener
      6443 # k3s API server (required for cluster nodes/pods)
      6881 # BitTorrent (double-check necessity; high exposure surface)
      8200 # MiniDLNA web UI (limit to LAN clients)
      9999 # KTorrent web UI (verify that WAN access is not required)
      10250 # kubelet metrics endpoint (scraped by observability stack)
      30400 # NVIDIA DCGM exporter metrics (Prometheus scrape)
    ];
    allowedUDPPorts = [
      53 # DNS resolver (Unbound)
      137 # Samba NetBIOS name service (LAN discovery)
      138 # Samba NetBIOS datagrams (LAN discovery)
      1900 # SSDP/UPnP discovery for MiniDLNA
      6881 # BitTorrent DHT/traffic (review before exposing beyond LAN)
      7881 # KTorrent DHT (peer discovery; ensure still needed)
      8881 # KTorrent UDP tracker (review necessity/exposure)
    ];
    # This is a reminder to address this when moving Urbit to skaia...
    # TODO: narrow the range of allowed UDP ports
    # allowedUDPPortRanges = [{ from = 13337; to = 65535; }];
    allowPing = true;
  };
}

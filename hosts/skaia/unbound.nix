{ config, lib, pkgs, ... }:

{
  # COLD START: Router DHCP must be updated to point LAN DNS to 192.168.0.160
  services.unbound = {
    enable = true;
    settings = {
      server = {
        # Bind on loopback for local resolution and on LAN IP for network clients
        interface = [ "127.0.0.1" "192.168.0.160" ];
        access-control = [
          "127.0.0.0/8 allow"
          "192.168.0.0/24 allow"
          # Allow k3s pod and service CIDRs so in-cluster pods can query Unbound
          "10.42.0.0/16 allow"
          "10.43.0.0/16 allow"
        ];
        verbosity = 1;
        hide-identity = "yes";
        hide-version = "yes";

        # Local authoritative zones
        # - veil.home.arpa: cluster services (MetalLB VIPs, ingresses, etc.)
        # - home.arpa: LAN hosts (skaia, meteors, hive, etc.)
        local-zone = [ "\"veil.home.arpa.\" static" "\"home.arpa.\" static" ];
        local-data = [
          # veil (cluster services)
          "\"ingress.veil.home.arpa. A 192.168.0.220\""
          "\"grafana.veil.home.arpa. A 192.168.0.220\""
          "\"prometheus.veil.home.arpa. A 192.168.0.220\""
          "\"alertmanager.veil.home.arpa. A 192.168.0.220\""
          "\"s3.veil.home.arpa. A 192.168.0.220\""
          "\"s3-console.veil.home.arpa. A 192.168.0.220\""
          "\"argocd.veil.home.arpa. A 192.168.0.220\""
          "\"argo-workflows.veil.home.arpa. A 192.168.0.220\""
          "\"argo-rollouts.veil.home.arpa. A 192.168.0.220\""

          # home (LAN hosts)
          "\"skaia.home.arpa. A 192.168.0.160\""
          "\"meteor-1.home.arpa. A 192.168.0.121\""
          "\"meteor-2.home.arpa. A 192.168.0.122\""
          "\"meteor-3.home.arpa. A 192.168.0.123\""
          "\"meteor-4.home.arpa. A 192.168.0.124\""
          "\"hive.home.arpa. A 192.168.0.144\""
          "\"homeassistant.home.arpa. A 192.168.0.184\""
        ];

        include = "/var/lib/unbound/rpz-local-zones.conf";
      };

      forward-zone = [
        {
          name = ".";
          # Upstream resolvers: router first, then Cloudflare
          forward-addr = [ "192.168.0.1" "1.1.1.1" "1.0.0.1" ];
        }
      ];
    };
  };

  # Ensure the include target exists to satisfy config checks even before first fetch
  systemd.tmpfiles.rules = [ "f /var/lib/unbound/rpz-local-zones.conf 0644 root root -" ];
}

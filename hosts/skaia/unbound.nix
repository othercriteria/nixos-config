{ config, lib, pkgs, ... }:

{
  # COLD START: Router DHCP must be updated to point LAN DNS to 192.168.0.160
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "127.0.0.1" "192.168.0.160" ];
        access-control = [
          "127.0.0.0/8 allow"
          "192.168.0.0/24 allow"
        ];
        verbosity = 1;
        hide-identity = "yes";
        hide-version = "yes";
      };

      forward-zone = [
        {
          name = ".";
          # Upstream resolvers: router first, then Cloudflare
          forward-addr = [ "192.168.0.1" "1.1.1.1" "1.0.0.1" ];
        }
      ];

      # Local authoritative zone for the home network
      local-zone = [ "veil.home.arpa. static" ];
      local-data = [
        "ingress.veil.home.arpa. A 192.168.0.220"
        "grafana.veil.home.arpa. A 192.168.0.220"
        "skaia.veil.home.arpa. A 192.168.0.160"
        "meteor-1.veil.home.arpa. A 192.168.0.121"
        "meteor-2.veil.home.arpa. A 192.168.0.122"
        "meteor-3.veil.home.arpa. A 192.168.0.123"
        "hive.veil.home.arpa. A 192.168.0.144"
      ];
    };
  };
}

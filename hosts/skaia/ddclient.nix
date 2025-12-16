{ config, ... }:

{
  # TODO: look into https://github.com/ryantm/agenix and sops-nix as
  # alternatives for secrets management
  services.ddclient = {
    enable = true;
    usev4 = "webv4, webv4=dynamicdns.park-your-domain.com/getip";
    usev6 = "";
    server = "dynamicdns.park-your-domain.com";
    domains = [ "@" "teleport" "urbit" "stiletto-demo" ];
    username = "valueof.info";
    passwordFile = "/etc/nixos/secrets/ddclient-password";
    protocol = "namecheap";
  };

  # Auto-retry on failure - handles transient race conditions during
  # nixos-rebuild switch when DynamicUser lookup may temporarily fail
  systemd.services.ddclient.serviceConfig = {
    Restart = "on-failure";
    RestartSec = "30s";
  };
}

{ config, lib, ... }:

{
  # TODO: look into https://github.com/ryantm/agenix and sops-nix as
  # alternatives for secrets management
  services.ddclient = {
    enable = true;
    usev4 = "webv4, webv4=dynamicdns.park-your-domain.com/getip";
    usev6 = "";
    server = "dynamicdns.park-your-domain.com";
    # `trivia` is updated only while the file host is on. Namecheap
    # dynamic DNS cannot create the A record; add host `trivia` in
    # the panel first or the update fails with "A record not Found".
    # Removing the label here does not delete the record. See
    # docs/runbooks/trivia-setup.md.
    domains = [
      "@"
      "teleport"
      "urbit"
      "stiletto-demo"
      "stream"
      "assistant"
      "ntfy"
    ]
    ++ lib.optionals config.custom.trivia.enable [ "trivia" ];
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

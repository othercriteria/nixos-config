{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ./gpu.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-4";
    hostId = "21c8b855";
  };

  custom = {
    teleportNode = {
      enable = true;
      tokenFile = "/etc/nixos/secrets/teleport/meteor-4.token"; # COLD START: populate with join token from skaia
      labels = {
        role = "k3s-server";
        site = "residence-1";
        gpu = "true";
      };
    };

    # Restrict the on-disk secrets footprint to only what this meteor's
    # services actually read. The deploy-time rsync syncs every plaintext
    # secret from the workspace; this scrubs everything else away at
    # activation. See modules/host-secrets-manifest.nix.
    hostSecretsManifest = {
      enable = true;
      allowed = [
        "veil-k3s-token"
        "teleport/meteor-4.token"
      ];
    };

    # Stream metrics to skaia's Netdata parent. View on skaia's dashboard
    # at netdata.home.arpa. See modules/netdata-child.nix.
    netdataChild.enable = true;
  };
}

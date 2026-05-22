{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-2";
    hostId = "63643165"; # COLD START: set a unique hostId after install
  };

  custom = {
    teleportNode = {
      enable = true;
      tokenFile = "/etc/nixos/secrets/teleport/meteor-2.token"; # COLD START: populate with join token from skaia
      labels = {
        role = "k3s-server";
        site = "residence-1";
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
        "teleport/meteor-2.token"
      ];
    };

    # Stream metrics to skaia's Netdata parent. View on skaia's dashboard
    # at netdata.home.arpa. See modules/netdata-child.nix.
    netdataChild.enable = true;
  };
}

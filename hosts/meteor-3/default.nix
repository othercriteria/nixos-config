{ config, lib, pkgs, pkgs-stable, ... }:

{
  imports = [
    ../server-common
    ./hardware-configuration.nix
    ../../modules/veil/firewall.nix
    ./k3s
  ];

  networking = {
    hostName = "meteor-3";
    hostId = "37363365"; # COLD START: set a unique hostId after install
  };

  custom.teleportNode = {
    enable = true;
    tokenFile = "/etc/nixos/secrets/teleport/meteor-3.token"; # COLD START: populate with join token from skaia
    labels = {
      role = "k3s-server";
      site = "residence-1";
    };
  };

  # Restrict the on-disk secrets footprint to only what this meteor's
  # services actually read. The deploy-time rsync syncs every plaintext
  # secret from the workspace; this scrubs everything else away at
  # activation. See modules/host-secrets-manifest.nix.
  custom.hostSecretsManifest = {
    enable = true;
    allowed = [
      "veil-k3s-token"
      "teleport/meteor-3.token"
    ];
  };
}

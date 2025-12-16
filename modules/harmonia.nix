{ config, lib, pkgs, ... }:

{
  # Harmonia - Fast Nix binary cache server
  # Serves the local nix store to other hosts on the LAN

  # COLD START: Generate the signing keypair before enabling:
  #
  #   nix-store --generate-binary-cache-key cache.home.arpa \
  #     secrets/harmonia-cache-private-key \
  #     assets/harmonia-cache-public-key.txt
  #
  #   git secret add secrets/harmonia-cache-private-key
  #   git secret hide
  #   git add secrets/harmonia-cache-private-key.secret assets/harmonia-cache-public-key.txt
  #
  # Then deploy to skaia and the key will be available at /etc/nixos/secrets/

  services.harmonia = {
    enable = true;
    signKeyPaths = [ "/etc/nixos/secrets/harmonia-cache-private-key" ];
    settings = {
      bind = "127.0.0.1:5380"; # Avoid 5000 (docker registry)
      workers = 4;
      max_connection_rate = 256;
      priority = 30; # Lower than cache.nixos.org (40) so local cache is preferred
    };
  };

}

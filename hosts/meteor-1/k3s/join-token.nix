{ config, lib, ... }:

{
  # COLD START: Ensure this file exists on the host with the correct token
  # Path managed by git-secret in the repo; copied to /etc/nixos/secrets
  services.k3s.tokenFile = lib.mkDefault "/etc/nixos/secrets/veil-k3s-token";
}

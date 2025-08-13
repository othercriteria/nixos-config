{ config, lib, ... }:

{
  # COLD START: Ensure this file exists on the host with the correct token
  services.k3s.tokenFile = lib.mkDefault "/etc/nixos/secrets/veil-k3s-token";
}

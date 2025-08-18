{ config, pkgs, lib, ... }:

{
  imports = [
    ../../../modules/veil/k3s-common.nix
  ];

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString ([
      "--cluster-init" # COLD START: run meteor-1 first
    ] ++ config.veil.k3s.commonFlags);
  };
}

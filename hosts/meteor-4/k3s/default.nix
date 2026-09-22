{ config, ... }:

{
  imports = [
    ../../../modules/veil/k3s-common.nix
    ../../../modules/k3s-nvidia-runtime.nix
  ];

  services.k3s = {
    enable = true;
    role = "server";
    extraFlags = toString (
      [
        "--server https://192.168.0.121:6443" # API server on meteor-1
        "--node-label=gpu=true"
      ]
      ++ config.veil.k3s.commonFlags
    );
  };
}

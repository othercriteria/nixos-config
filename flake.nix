{
  description = "NixOS configuration with development environment and secret detection";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";
  };
  outputs =
    { self
    , nixpkgs
    , flake-utils
    , pre-commit-hooks
    , ...
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      devShell = pkgs.mkShell {
        buildInputs = with pkgs; [
          gnumake
          git
          git-secret
          nixpkgs-fmt
          deadnix
          statix
          pre-commit
          detect-secrets
        ];
        shellHook = ''
          pre-commit install
        '';
      };
    in
    {
      devShells.default = devShell;
      packages.default = pkgs.stdenv.mkDerivation {
        pname = "nixos-config";
        version = "1.0";
        src = ./.;
        buildInputs = with pkgs; [
          # Add necessary build inputs
        ];
        # Define build phases if necessary
      };
      # You can add more outputs like apps, overlays, etc.
    }
    );
}

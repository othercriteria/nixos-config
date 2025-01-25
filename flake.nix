{
  description = "NixOS configuration with development environment and secret detection";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    # Add other necessary inputs here
    #pre-commit-hooks.url = "github:pre-commit/pre-commit-hooks";
  };
  outputs =
    { self
    , nixpkgs
    , flake-utils
    , #pre-commit-hooks, 
      ...
    }:
    flake-utils.lib.eachDefaultSystem (system:
    let
      pkgs = nixpkgs.legacyPackages.${system};
      devShell = pkgs.mkShell {
        buildInputs = with pkgs; [
          gnumake
          git
          # Add other development tools here
          nixpkgs-fmt
          #pre-commit
        ];
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

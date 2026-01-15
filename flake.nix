{
  description = "NixOS configuration with development environment and secret detection";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    # This should be the latest stable release, used to
    # rollback broken versions in unstable
    # TODO: bump this!
    nixpkgs-stable.url = "github:NixOS/nixpkgs/nixos-24.11";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    flake-utils.url = "github:numtide/flake-utils";

    pre-commit-hooks.url = "github:cachix/pre-commit-hooks.nix";

    # Python packaging helpers (uv2nix + ecosystem)
    pyproject-nix = {
      url = "github:pyproject-nix/pyproject.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    uv2nix = {
      url = "github:pyproject-nix/uv2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.pyproject-nix.follows = "pyproject-nix";
    };

    pyproject-build-systems = {
      url = "github:pyproject-nix/build-system-pkgs";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        pyproject-nix.follows = "pyproject-nix";
        uv2nix.follows = "uv2nix";
      };
    };

  };

  outputs = { self, nixpkgs, nixpkgs-stable, home-manager, flake-utils, pre-commit-hooks, pyproject-nix, uv2nix, pyproject-build-systems, ... }:
    let
      supportedSystems = [ "x86_64-linux" ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;
    in
    {
      # NixOS configurations
      nixosConfigurations = {
        skaia = nixpkgs.lib.nixosSystem rec{
          system = "x86_64-linux";
          specialArgs = {
            pkgs-stable = import nixpkgs-stable {
              inherit system;
              config.allowUnfree = true;
            };
            inherit uv2nix;
            pyprojectNix = pyproject-nix;
            pyprojectBuildSystems = pyproject-build-systems;
          };
          modules = [
            ./hosts/skaia
            home-manager.nixosModules.home-manager
            ({ pkgs, ... }: {
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = {
                  twsPackage = import ./modules/tws.nix { inherit pkgs; };
                };
                users.dlk = import ./home;
              };
            })
          ];
        };

        meteor-1 = nixpkgs.lib.nixosSystem rec{
          system = "x86_64-linux";
          specialArgs = {
            pkgs-stable = import nixpkgs-stable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          modules = [
            ./hosts/meteor-1
          ];
        };

        meteor-2 = nixpkgs.lib.nixosSystem rec{
          system = "x86_64-linux";
          specialArgs = {
            pkgs-stable = import nixpkgs-stable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          modules = [
            ./hosts/meteor-2
          ];
        };

        meteor-3 = nixpkgs.lib.nixosSystem rec{
          system = "x86_64-linux";
          specialArgs = {
            pkgs-stable = import nixpkgs-stable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          modules = [
            ./hosts/meteor-3
          ];
        };

        meteor-4 = nixpkgs.lib.nixosSystem rec{
          system = "x86_64-linux";
          specialArgs = {
            pkgs-stable = import nixpkgs-stable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          modules = [
            ./hosts/meteor-4
          ];
        };

        hive = nixpkgs.lib.nixosSystem rec{
          system = "x86_64-linux";
          specialArgs = {
            pkgs-stable = import nixpkgs-stable {
              inherit system;
              config.allowUnfree = true;
            };
          };
          modules = [
            ./hosts/hive
          ];
        };

        # Demo VM for portfolio exploration (no hardware deps, no secrets)
        # Build: nixos-rebuild build-vm --flake .#demo
        # Run:   ./result/bin/run-demo-vm
        demo = nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            ./hosts/demo
          ];
        };
      };
    } // (flake-utils.lib.eachSystem supportedSystems (system:
      let
        pkgs = nixpkgs.legacyPackages.${system};
      in
      {
        # Integration tests
        # Run with: nix flake check
        # Or build specific test: nix build .#checks.x86_64-linux.observability
        checks = {
          observability = import ./tests/observability.nix { inherit pkgs; };
        };

        # Development environment
        devShells.default = pkgs.mkShell {
          buildInputs = with pkgs; [
            gnumake
            git
            git-lfs
            git-secret
            nixpkgs-fmt
            deadnix
            statix
            pre-commit
            detect-secrets
            gitleaks
            nodePackages.markdownlint-cli
          ];
          shellHook = ''
            if [ ! -d private-assets ]; then
              echo "Warning: private-assets submodule not found."
              echo "Run 'make add-private-assets' to add it."
            fi
            if [ ! -d gitops-veil ]; then
              echo "Note: gitops-veil submodule not found."
              echo "Run 'make add-gitops-veil' if you need veil cluster GitOps access."
            fi
            pre-commit install
          '';
        };
      }));
}

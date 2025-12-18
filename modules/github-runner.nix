# GitHub Actions Self-Hosted Runner
#
# Declarative configuration for a self-hosted GitHub Actions runner.
# Uses the built-in NixOS module (services.github-runners).
#
# COLD START: Generate a fine-grained PAT with "Read and Write access to
# repository self hosted runners" scope, then:
#
#   echo -n 'github_pat_...' > secrets/github-runner-token
#   git secret add secrets/github-runner-token
#   git secret hide
#
# The runner will auto-register on first start and re-register as needed.

{ config, lib, pkgs, ... }:

let
  cfg = config.custom.githubRunner;
in
{
  options.custom.githubRunner = {
    enable = lib.mkEnableOption "GitHub Actions self-hosted runner";

    url = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/othercriteria/nixos-config";
      description = "Repository URL for the runner to register with.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.path;
      default = "/etc/nixos/secrets/github-runner-token";
      description = ''
        Path to file containing a fine-grained PAT with runner admin scope.
        Must not have a trailing newline (use `echo -n`).
      '';
    };

    name = lib.mkOption {
      type = lib.types.str;
      default = config.networking.hostName;
      description = "Runner name (defaults to hostname).";
    };

    extraLabels = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "nixos" ];
      description = "Additional labels for the runner.";
    };

    kvmAccess = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to grant KVM access for NixOS VM tests.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Create a dedicated user for the runner
    users.users.github-runner = {
      isSystemUser = true;
      group = "github-runner";
      # Add to kvm group for NixOS integration tests
      extraGroups = lib.optionals cfg.kvmAccess [ "kvm" ];
      home = "/var/lib/github-runner";
      createHome = true;
    };
    users.groups.github-runner = { };

    services.github-runners.${cfg.name} = {
      enable = true;
      inherit (cfg) url tokenFile name;

      # Labels for workflow targeting
      extraLabels = cfg.extraLabels ++ lib.optionals cfg.kvmAccess [ "kvm" ];

      # Packages available to workflows
      extraPackages = with pkgs; [
        # Nix tooling
        nix
        nixVersions.stable
        cachix

        # Build essentials
        git
        git-lfs
        gnumake
        coreutils
        bash

        # CI utilities
        curl
        jq
        findutils
        gnugrep
        gnused

        # Linting tools (so workflows don't need to nix run each time)
        statix
        deadnix
        nixpkgs-fmt
      ];

      # Environment for nix commands
      extraEnvironment = {
        NIX_CONFIG = "experimental-features = nix-command flakes";
        # Trust the local nix store for builds
        HOME = "/var/lib/github-runner";
      };

      # Run as dedicated user
      user = "github-runner";
      group = "github-runner";

      # Ephemeral mode: fresh state each job (recommended for security)
      # Each job gets a clean environment, runner re-registers after each job
      ephemeral = true;

      # Replace existing runner with same name on registration
      replace = true;

      # Allow access to nix daemon and (optionally) KVM
      serviceOverrides = {
        # KVM group access for NixOS VM tests
        SupplementaryGroups = lib.optionals cfg.kvmAccess [ "kvm" ];

        # Allow /dev/kvm access for NixOS VM tests
        DeviceAllow = lib.optionals cfg.kvmAccess [ "/dev/kvm rw" ];

        # Relax sandbox for nix builds
        ProtectHome = "read-only";
        ProtectSystem = "strict";
        ReadWritePaths = [
          "/nix/var"
          "/var/lib/github-runner"
        ];
      };
    };

    # Ensure nix trusts the runner user for building
    nix.settings.trusted-users = [ "github-runner" ];
  };
}

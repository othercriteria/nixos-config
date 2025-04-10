{ config, lib, pkgs, ... }:

# vibectl NixOS module
#
# This module provides system-wide integration of the vibectl CLI tool,
# a vibes-based alternative to kubectl for interacting with Kubernetes clusters.
#
# Key features:
# - No network dependency during build (compatible with Nix's sandboxed build)
# - Proper Python module path handling and dependency management
# - Wrapping with correct environment variables and PATH integration
# - Support for Claude AI models via llm-anthropic plugin
# - Creates a temporary home directory during build to prevent permission issues
#
# TODO:
# - Consider pinning specific versions of dependencies for better build reproducibility
# - Consider using flake inputs for better version management
# - Add more LLM plugins as needed

with lib;

let
  cfg = config.custom.vibectl;
in
{
  options.custom.vibectl = {
    enable = mkEnableOption "Enable vibectl, a vibes-based alternative to kubectl";

    anthropicApiKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Anthropic API key for vibectl to use Claude models";
      example = "sk-ant-api123...";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (
        let
          # Create a Python environment with required packages including llm from nixpkgs
          pythonEnv = pkgs.python312.withPackages (ps: with ps; [
            # Core dependencies
            click
            rich
            kubernetes
            requests
            pyyaml
            pydantic

            # LLM and Anthropic plugin from nixpkgs
            llm
            llm-anthropic

            # Build dependencies
            pip
            setuptools
            wheel
            hatchling
          ]);
        in
        pkgs.stdenv.mkDerivation {
          pname = "vibectl";
          version = "0.2.2";

          src = pkgs.fetchFromGitHub {
            owner = "othercriteria";
            repo = "vibectl";
            rev = "v0.2.2"; # Using specific release tag
            sha256 = "sha256-RLAxg1jEUug3bLn0sPdewf0hUHmBX1qZg868odaLqXE="; # pragma: allowlist secret
          };

          # Need nativeBuildInputs for build-time dependencies
          nativeBuildInputs = [
            pythonEnv
            pkgs.makeWrapper
          ];

          # Skip configure phase as we're not using autotools
          dontConfigure = true;

          # Skip Python's build isolation to use our environment
          buildPhase = ''
            # Create a writable home directory for pip
            export HOME=$(mktemp -d)

            # Install with pip but don't use --prefix which doesn't properly setup paths
            mkdir -p $out/${pythonEnv.sitePackages}
            cp -r vibectl $out/${pythonEnv.sitePackages}/

            # Create bin directory and script
            mkdir -p $out/bin
            cat > $out/bin/vibectl << EOF
            #!${pythonEnv.interpreter}
            import sys
            from vibectl.cli import cli

            if __name__ == "__main__":
                sys.exit(cli())
            EOF
            chmod +x $out/bin/vibectl
          '';

          # No separate install phase needed
          dontInstall = true;

          # Wrap the executable to ensure it can find dependencies
          postFixup = ''
            wrapProgram $out/bin/vibectl \
              --prefix PYTHONPATH : "$out/${pythonEnv.sitePackages}:${pythonEnv}/${pythonEnv.sitePackages}" \
              --prefix PATH : "${pkgs.kubectl}/bin" \
              ${optionalString (cfg.anthropicApiKey != null) "--set ANTHROPIC_API_KEY \"${cfg.anthropicApiKey}\""}
          '';

          meta = with lib; {
            description = "A vibes-based alternative to kubectl for interacting with Kubernetes clusters";
            homepage = "https://github.com/othercriteria/vibectl";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        }
      )
    ];
  };
}

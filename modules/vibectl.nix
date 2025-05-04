{ config, lib, pkgs, ... }:

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

    anthropicApiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to a file containing the Anthropic API key";
      example = "/etc/nixos/secrets/anthropic-2025-04-10-vibectl-personal-usage";
    };

    openaiApiKey = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "OpenAI API key for vibectl to use GPT models";
      example = "sk-abc123...";
    };

    openaiApiKeyFile = mkOption {
      type = types.nullOr types.str;
      default = null;
      description = "Path to a file containing the OpenAI API key";
      example = "/etc/nixos/secrets/openai-key";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (
        let
          # Create a Python environment with required packages
          pythonEnv = pkgs.python312.withPackages (ps: with ps; [
            # Core dependencies
            click
            rich
            kubernetes
            requests
            pyyaml
            pydantic

            # LLM integration (still required despite improved key management)
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
          version = "0.6.0";

          src = pkgs.fetchFromGitHub {
            owner = "othercriteria";
            repo = "vibectl";
            rev = "v0.6.0"; # Official v0.3.0 release tag
            sha256 = "sha256-/pscGe9XaXyDYz0UWJmaotqskXkTromSRM4+jKLkK2M="; # Hash for v0.6.0 tag # pragma: allowlist secret
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
            import os
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
              --prefix PATH : "${pkgs.kubectl}/bin:${pythonEnv}/bin" \
              ${optionalString (cfg.anthropicApiKey != null) "--set VIBECTL_ANTHROPIC_API_KEY \"${cfg.anthropicApiKey}\""} \
              ${optionalString (cfg.anthropicApiKeyFile != null) "--set VIBECTL_ANTHROPIC_API_KEY_FILE \"${cfg.anthropicApiKeyFile}\""} \
              ${optionalString (cfg.openaiApiKey != null) "--set VIBECTL_OPENAI_API_KEY \"${cfg.openaiApiKey}\""} \
              ${optionalString (cfg.openaiApiKeyFile != null) "--set VIBECTL_OPENAI_API_KEY_FILE \"${cfg.openaiApiKeyFile}\""}
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

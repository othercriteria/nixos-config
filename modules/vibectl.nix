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
# - IMPORTANT: The llm package manages its own keys separate from environment variables
#   which can cause conflicts between vibectl and other tools using the same LLM APIs
# - Consider using a dedicated config directory for vibectl to avoid key conflicts

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
            import os
            import subprocess
            import shutil
            import json
            import pathlib
            import time

            # TODO: RICKETY HACK - This is a temporary solution to avoid the slow llm command
            # Future improvements needed:
            # - Migrate to a dedicated vibectl config system separate from llm's
            # - Add better isolation between vibectl and other llm users
            # - Create a proper config management system inside vibectl
            # - Handle API key rotation and updates more elegantly
            # - Consider having a wrapper script that pre-loads keys
            # - Time performance of different key loading strategies

            # Timing helper
            def time_operation(operation_name, func, *args, **kwargs):
                start_time = time.time()
                result = func(*args, **kwargs)
                end_time = time.time()
                duration_ms = (end_time - start_time) * 1000
                if duration_ms > 100:  # Only log slow operations
                    print(f"Performance warning: {operation_name} took {duration_ms:.2f}ms")
                return result

            # Get llm keys file path - avoid calling the slow llm command
            def get_llm_keys_file():
                # Common locations for llm keys file based on platform
                config_dir = os.environ.get("XDG_CONFIG_HOME")
                if not config_dir:
                    home = os.path.expanduser("~")
                    config_dir = os.path.join(home, ".config")

                # Standard llm config path
                llm_keys_file = os.path.join(config_dir, "io.datasette.llm", "keys.json")

                if os.path.exists(llm_keys_file):
                    return llm_keys_file

                # Fallback to slow llm command if we can't find the file
                try:
                    result = subprocess.run(
                        ["llm", "keys", "path"],
                        stderr=subprocess.PIPE,
                        stdout=subprocess.PIPE,
                        text=True,
                        check=True
                    )
                    return result.stdout.strip()
                except Exception:
                    return None

            # Check if llm is available - required for vibectl functionality
            llm_path = shutil.which("llm")
            if not llm_path:
                print("Error: The 'llm' command was not found in PATH.")
                print("vibectl requires the llm package to function correctly.")
                print("Please ensure the llm Python package is installed and accessible.")
                sys.exit(1)

            # Get the keys file path
            llm_keys_file = time_operation("Get llm keys file path", get_llm_keys_file)

            if not llm_keys_file or not os.path.isfile(llm_keys_file):
                print("Error: Could not locate llm keys file.")
                print("Please run 'llm keys path' to ensure keys storage is configured.")
                sys.exit(1)

            # Read existing keys directly from file (much faster than llm command)
            try:
                with open(llm_keys_file, 'r') as f:
                    keys_data = json.load(f)
            except (json.JSONDecodeError, FileNotFoundError):
                keys_data = {"// Note": "This file stores secret API credentials. Do not share!"}

            # Check if API key file path is set and load it
            api_key_file = os.environ.get('ANTHROPIC_API_KEY_FILE')
            if api_key_file and os.path.isfile(api_key_file):
                with open(api_key_file, 'r') as f:
                    api_key = f.read().strip()

                    # Only update the keys file if the key has changed or is missing
                    current_key = keys_data.get("anthropic", "")
                    if current_key != api_key:
                        # Update the key in the keys data
                        keys_data["anthropic"] = api_key

                        # Make parent directory if needed
                        pathlib.Path(llm_keys_file).parent.mkdir(parents=True, exist_ok=True)

                        # Write the updated keys back to the file
                        try:
                            with open(llm_keys_file, 'w') as f:
                                json.dump(keys_data, f, indent=2)
                        except Exception as e:
                            print(f"Error: Failed to update llm keys file: {e}")
                            print("Falling back to llm command")
                            try:
                                subprocess.run(
                                    ["llm", "keys", "set", "anthropic", "--value", api_key],
                                    stderr=subprocess.PIPE,
                                    stdout=subprocess.PIPE,
                                    check=True
                                )
                            except subprocess.CalledProcessError as e:
                                print(f"Error: Failed to set Anthropic API key for llm: {e}")
                                sys.exit(1)

            # Add debug flag to show which key is being used
            if len(sys.argv) > 1 and sys.argv[1] == "--show-key":
                # Read directly from the keys file instead of using llm command
                key = keys_data.get("anthropic", "Not set")
                key_source = f"From llm keys file: {llm_keys_file}"

                if key == "Not set":
                    print("No Anthropic API key found in llm's key store.")
                    print("Run vibectl with a properly configured API key file.")
                    sys.exit(1)

                first_chars = key[:10] if len(key) > 10 else key
                last_chars = key[-5:] if len(key) > 5 else ""
                print(f"API Key: {first_chars}...{last_chars}")
                print(f"Source: {key_source}")
                print(f"Size: {len(key)} characters")
                sys.exit(0)

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
              ${optionalString (cfg.anthropicApiKey != null) "--set ANTHROPIC_API_KEY \"${cfg.anthropicApiKey}\""} \
              ${optionalString (cfg.anthropicApiKeyFile != null) "--set ANTHROPIC_API_KEY_FILE \"${cfg.anthropicApiKeyFile}\""}
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

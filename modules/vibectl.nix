{ config, lib, pkgs, uv2nix, pyprojectNix, pyprojectBuildSystems, ... }:

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

    anthropicPlugin = mkOption {
      type = types.nullOr types.bool;
      default = null;
      description = "Whether to include the llm-anthropic plugin. If null (default), the plugin will be included automatically when an Anthropic API key or key file is provided.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      (
        let
          src = pkgs.fetchFromGitHub {
            owner = "othercriteria";
            repo = "vibectl";
            # NOTE: update when bumping vibectl; use the same commit until a new
            # release is pinned.
            rev = "87d231c20d1833b92d996f2549a61cf97f8aea30"; # pragma: allowlist secret
            sha256 = "sha256-ls5f/jPvq08gdR9Fn4L+TmPbVBHi56xPnyo2T2885q8="; # pragma: allowlist secret
          };

          # Build via uv2nix workspace → overlay → pythonSet → virtualenv

          workspace = uv2nix.lib.workspace.loadWorkspace { workspaceRoot = src; };

          overlay = workspace.mkPyprojectOverlay {
            sourcePreference = "wheel";
          };

          # Determine if the llm-anthropic plugin should be included
          pluginNeeded = if cfg.anthropicPlugin != null then cfg.anthropicPlugin else (cfg.anthropicApiKey != null || cfg.anthropicApiKeyFile != null);

          # Optional llm-anthropic plugin derivation
          anthropicPluginDrv = pkgs.python312Packages.buildPythonPackage rec {
            # PyPI uses underscores for the source archive name
            pname = "llm_anthropic";
            version = "0.17";
            format = "pyproject";
            src = pkgs.fetchPypi {
              inherit pname version;
              sha256 = "sha256-L14atbfrmoS40HRzqGlwiLZZ/U8ZQdloY88Yz4z7nrA="; # pragma: allowlist secret
            };
            propagatedBuildInputs = with pkgs.python312Packages; [ llm anthropic ];
            pythonImportsCheck = [ "llm_anthropic" ];
          };

          pythonSet = (pkgs.callPackage pyprojectNix.build.packages { python = pkgs.python312; }).overrideScope (lib.composeManyExtensions [
            pyprojectBuildSystems.overlays.default
            overlay
          ]);

          base = pythonSet.mkVirtualEnv "vibectl-env" workspace.deps.default;


        in
        base.overrideAttrs (old:
          let
            pythonVer = lib.versions.majorMinor pkgs.python312.version; # e.g. "3.12"
            sitePkgs = "$out/lib/python${pythonVer}/site-packages";
          in
          {
            nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ pkgs.makeWrapper ] ++ lib.optional pluginNeeded anthropicPluginDrv;

            postInstall = (old.postInstall or "") + lib.optionalString pluginNeeded ''
              # Include llm-anthropic plugin in the virtualenv
              pluginSitePkgs=${anthropicPluginDrv}/lib/python${pythonVer}/site-packages
              cp -r "$pluginSitePkgs"/* "${sitePkgs}/"

              # Also copy the required anthropic dependency
              anthropicSitePkgs=${pkgs.python312Packages.anthropic}/lib/python${pythonVer}/site-packages
              cp -r "$anthropicSitePkgs"/* "${sitePkgs}/"
            '';

            postFixup = (old.postFixup or "") + ''
              for prog in $out/bin/vibectl $out/bin/vibectl-server; do
                if [ -f "$prog" ]; then
                  # Create a wrapped version that ensures Python can find the
                  # installed modules and that kubectl is available.

                  mv "$prog" "$prog.orig"

                  makeWrapper "$prog.orig" "$prog" \
                    --set PYTHONPATH "${sitePkgs}" \
                    --prefix PATH : "${pkgs.kubectl}/bin" \
                    ${optionalString (cfg.anthropicApiKey     != null) "--set VIBECTL_ANTHROPIC_API_KEY ${cfg.anthropicApiKey}"} \
                    ${optionalString (cfg.anthropicApiKeyFile != null) "--set VIBECTL_ANTHROPIC_API_KEY_FILE ${cfg.anthropicApiKeyFile}"} \
                    ${optionalString (cfg.openaiApiKey        != null) "--set VIBECTL_OPENAI_API_KEY ${cfg.openaiApiKey}"} \
                    ${optionalString (cfg.openaiApiKeyFile    != null) "--set VIBECTL_OPENAI_API_KEY_FILE ${cfg.openaiApiKeyFile}"}

                fi
              done
            '';
          })
      )
    ];
  };
}

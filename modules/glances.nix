# Glances 4.5.7 depends on python-jose, which this nixpkgs refuses to
# evaluate (CVE-2026-120459: an empty HMAC key forges JWTs). Glances
# 4.5.9 replaces python-jose with PyJWT. This is nixpkgs PR #587533.
# Drop the overlay once the flake carries that version.
#
# The REST and XML-RPC tests still talk to 127.0.0.1 from the sandbox
# and fail the same way they did on 4.5.6 and 4.5.7.
{ lib, ... }:
{
  nixpkgs.overlays = [
    (_final: prev: {
      glances = prev.python3Packages.buildPythonApplication (finalAttrs: {
        pname = "glances";
        version = "4.5.9";
        pyproject = true;

        src = prev.fetchFromGitHub {
          owner = "nicolargo";
          repo = "glances";
          tag = "v${finalAttrs.version}";
          hash = "sha256-CvT9GQ29xXTVxC7V2nGmfDhHLsAtF61+XMMLG8cmHww="; # pragma: allowlist secret
        };

        build-system = with prev.python3Packages; [ setuptools ];

        makeWrapperArgs = lib.optionals prev.stdenv.hostPlatform.isDarwin [
          "--set"
          "DYLD_FRAMEWORK_PATH"
          "/System/Library/Frameworks"
        ];

        doCheck = !prev.stdenv.hostPlatform.isDarwin;

        dependencies =
          with prev.python3Packages;
          [
            defusedxml
            packaging
            psutil
            pyinstrument
            pysnmp
            fastapi
            uvicorn
            requests
            jinja2
            pyjwt
            prometheus-client
            shtab
          ]
          ++ [ prev.which ]
          ++ lib.optionals prev.stdenv.hostPlatform.isLinux [ prev.hddtemp ];

        nativeCheckInputs =
          with prev.python3Packages;
          [
            chevron
            pysmart
            pytestCheckHook
            selenium
          ]
          ++ [
            prev.podman
            prev.which
          ];

        disabledTestPaths = [
          # Message: Unable to obtain driver for chrome
          "tests/test_webui.py"
          "tests/test_restful.py"
          "tests/test_browser_restful.py"
          "tests/test_xmlrpc.py"
        ];

        disabledTests = [
          "test_msg_curse_returns_list"
          "test_msg_curse_with_max_width"
          "test_glances_api_plugin_network"
          "test_perf_update"
          "test_pipe"
        ];

        meta = {
          homepage = "https://nicolargo.github.io/glances/";
          description = "Cross-platform curses-based monitoring tool";
          mainProgram = "glances";
          license = lib.licenses.lgpl3Only;
        };
      });
    })
  ];
}

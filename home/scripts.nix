{ pkgs, ... }:

# User commands whose bodies live in assets/. writeShellApplication puts
# runtimeInputs on PATH and enables nounset and pipefail.
let
  script =
    name: runtimeInputs:
    pkgs.writeShellApplication {
      inherit name runtimeInputs;
      text = builtins.readFile ../assets/${name}.sh;
    };

  tailsayPy = pkgs.writers.writePython3Bin "tailsay-py" {
    libraries = [ pkgs.python3Packages.websockets ];
    flakeIgnore = [
      "E265"
      "E501"
      "W503"
    ];
  } (builtins.readFile ../assets/wscatsay.py);
in
{
  home.packages = [
    # Token and server for assistant.home.arpa. Raw `hass-cli` stays in
    # home/default.nix.
    (script "hass" [ pkgs.home-assistant-cli ])

    # ollama CLI pointed at ollama.home.arpa. `ask` is the one-shot chat.
    (script "oll" [ pkgs.ollama ])
    (script "ask" [ pkgs.ollama ])

    # Batch TTS. tailsay is the streaming counterpart (assets/wscatsay.py).
    (script "catsay" [
      pkgs.jq
      pkgs.curl
      pkgs.ffmpeg
      pkgs.pulseaudio
      pkgs.coreutils
    ])
    (script "tailsay" [
      pkgs.ffmpeg
      tailsayPy
    ])
  ];
}

# Ollama: Local LLM inference with CUDA acceleration
#
# Provides:
# - Ollama service on localhost:11434 (exposed via nginx at ollama.home.arpa)
# - Model tags pulled at boot (loadModels runs `ollama pull`; it does
#   not pin weights in VRAM)
# - OLLAMA_DEFAULT_MODEL env var for scripts to reference
# - ollama-background.target for low-priority Ollama clients
#
# Usage from LAN:
#   curl http://ollama.home.arpa/api/generate -d '{"model":"qwen2.5:14b-instruct-q8_0","prompt":"Hi"}'
#
# OpenAI-compatible endpoint (for MCP, LangChain, etc.):
#   http://ollama.home.arpa/v1/chat/completions
#
# Used by:
# - Home Assistant Assist (Settings -> Devices & Services -> Ollama),
#   pointed at http://ollama.home.arpa with the qwen3.5:9b-q8_0 model
#   (see haAssistantModel below). HA's CoreDNS forwards home.arpa to
#   skaia's unbound (set on the HA Yellow via `ha dns options
#   --servers dns://192.168.0.160`), so the Ollama integration container
#   resolves the FQDN natively - no need to broaden the bind address.
# - Local scripts (ask, MCP, etc.) via $OLLAMA_DEFAULT_MODEL.
# - Waybar's weather vibe, on the HA model, via ollama-background.target
#   (below). HA Assist is not a member of that target.

{ pkgs, ... }:

let
  # Default model for interactive use and scripts (ask, MCP, etc.)
  # qwen2.5:14b-instruct-q8_0: best latency/quality tradeoff
  # - ~11GB VRAM, ~0.3s response warm, ~2-3s cold
  # - "GPT-4o-mini class" quality, q8_0 is essentially lossless
  # For complex reasoning tasks, pull qwen2.5:32b and use ASK_MODEL override
  defaultModel = "qwen2.5:14b-instruct-q8_0";

  # Conversation agent for Home Assistant Assist (Phase C of the voice
  # build-out). Wired into HA via the Ollama integration; the model is
  # responsible for parsing free-form user requests, picking the right
  # HA tools, and stitching them together.
  #
  # 2026-08: qwen3:8b-q8_0 -> qwen3.5:9b-q8_0. Same q8 slot (~11 GB
  # weights; a warm Qwen3 8B sat at ~13 GB with KV cache). Qwen3.5 9B
  # is the current 8–9B default and matches the 14b-instruct-q8_0
  # quant we already trust for quality. Official library tag, not a
  # fork. HA's Ollama integration stores the model name in the HA UI
  # (Settings -> Devices & Services -> Ollama) - change it there after
  # apply or Assist keeps calling the old tag.
  #
  # Also used by the weather-emoji vibe (assets/weather-emoji.py).
  # Sharing one resident model avoids a second VRAM load. The script
  # hardcodes the name rather than reading it from Nix.
  #
  # A warm 9B at 32K context is about 11 GB. The 14B is another
  # ~11 GB of weights before KV. They do not both stay resident on
  # the 24 GB 4090 next to speech. See kokoro.nix.
  haAssistantModel = "qwen3.5:9b-q8_0";

  weatherEmoji = pkgs.writeText "weather-emoji.py" (builtins.readFile ../../assets/weather-emoji.py);

  # Ordinary-user wrapper. Polkit below allows dlk to manage the
  # target; status needs nothing. Members are PartOf the target, so
  # this does not name them in the start/stop path.
  ollamaBackground = pkgs.writeShellScriptBin "ollama-background" ''
    set -eu
    usage() {
      echo "usage: ollama-background {start|stop|restart|status}" >&2
      exit 2
    }
    cmd=''${1:-status}
    case "$cmd" in
      start|stop|restart)
        exec systemctl "$cmd" ollama-background.target
        ;;
      status)
        exec systemctl --no-pager status \
          ollama-background.target \
          ollama-background-gate.service \
          weather-emoji.timer \
          weather-emoji.service
        ;;
      *)
        usage
        ;;
    esac
  '';
in
{
  services.ollama = {
    enable = true;
    package = pkgs.ollama-cuda;
    host = "127.0.0.1"; # Bind localhost; nginx handles LAN exposure
    port = 11434;
    loadModels = [
      defaultModel
      haAssistantModel
    ];
  };

  # Export default model so user scripts can reference it
  environment.sessionVariables = {
    OLLAMA_DEFAULT_MODEL = defaultModel;
  };

  # Ensure ollama CLI is available system-wide
  environment.systemPackages = [
    pkgs.ollama
    ollamaBackground
  ];

  # Low-priority Ollama clients. Same shape as gpu-voice.target:
  # wanted at boot, one polkit-gated verb, members opt in with
  # wantedBy + PartOf. Stopping the target stops those clients from
  # issuing requests. It does not stop the daemon, HA Assist, or
  # `ask`, and it does not `ollama stop` a shared model. The last
  # keep_alive still runs out, and HA may be holding the weights.
  #
  # The gate service is the admission bit. It stays up
  # (RemainAfterExit) for the life of the target and removes
  # /run/ollama-background/enabled when the target stops. Member
  # units are PartOf the target, so a stop also kills a request
  # already in flight. A member must still check the gate before any
  # new request and exit success when the file is absent, so a unit
  # started by hand cannot reload a model after the stop.
  #
  # Add a client by:
  # 1. wantedBy + PartOf = ollama-background.target (a timer, if the
  #    work is periodic; do not also exec it from a user session).
  # 2. Check the gate file before any request, and exit success when
  #    it is absent.
  # 3. Do not unload a model another client still uses. Weather
  #    shares haAssistantModel with HA Assist.
  systemd = {
    targets.ollama-background = {
      description = "Low-priority Ollama clients";
      wantedBy = [ "multi-user.target" ];
    };

    services.ollama-background-gate = {
      description = "Allow low-priority Ollama clients to run";
      wantedBy = [ "ollama-background.target" ];
      unitConfig.PartOf = [ "ollama-background.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "ollama-background";
        RuntimeDirectoryMode = "0755";
        ExecStart = "${pkgs.coreutils}/bin/touch /run/ollama-background/enabled";
      };
    };

    # Weather vibe. Waybar only reads the published snapshot
    # (~/.cache/waybar-weather-emoji/latest.json). This timer is the
    # only thing that calls the model. 10 minutes matches the old
    # Waybar interval; the script's own cache still skips Ollama when
    # the METAR and the time-of-day bucket have not changed.
    services.weather-emoji = {
      description = "Refresh the Waybar weather vibe";
      unitConfig.PartOf = [ "ollama-background.target" ];
      after = [
        "network-online.target"
        "ollama.service"
        "ollama-background-gate.service"
      ];
      wants = [
        "network-online.target"
        "ollama.service"
      ];
      serviceConfig = {
        Type = "oneshot";
        User = "dlk";
        Environment = [ "HOME=/home/dlk" ];
        ExecStart = "${pkgs.python3}/bin/python3 ${weatherEmoji} --refresh";
        TimeoutStartSec = "90s";
      };
    };

    timers.weather-emoji = {
      description = "Refresh the Waybar weather vibe";
      wantedBy = [ "ollama-background.target" ];
      unitConfig.PartOf = [ "ollama-background.target" ];
      after = [ "ollama-background-gate.service" ];
      timerConfig = {
        OnActiveSec = "90s";
        OnUnitInactiveSec = "10min";
        AccuracySec = "30s";
      };
    };
  };

  # systemctl start/stop/restart as user dlk, no password. Status is
  # unprivileged. Propagation via PartOf happens inside pid 1, so the
  # member units do not need their own rules.
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if (
        action.id == "org.freedesktop.systemd1.manage-units" &&
        subject.user == "dlk" &&
        action.lookup("unit") == "ollama-background.target"
      ) {
        var verb = action.lookup("verb");
        if (verb == "start" || verb == "stop" || verb == "restart") {
          return polkit.Result.YES;
        }
      }
    });
  '';
}

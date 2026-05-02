# Voice assistant server-side stack on skaia.
#
# Currently provides:
# - Wyoming faster-whisper STT server  on tcp://skaia.home.arpa:10300
# - Wyoming F5-TTS proxy               on tcp://skaia.home.arpa:10200
# - Wyoming Kokoro proxy (a/b candidate) on tcp://skaia.home.arpa:10210
#
# Used by:
# - Home Assistant's Wyoming integration (Settings -> Devices & Services ->
#   Add -> Wyoming Protocol). Add one entry per service:
#     STT: skaia.home.arpa:10300
#     TTS (F5):     skaia.home.arpa:10200
#     TTS (Kokoro): skaia.home.arpa:10210
#   Both TTS endpoints are wired in parallel so we can flip the active
#   engine in the HA Assist pipeline (Settings -> Voice assistants ->
#   <pipeline> -> Text-to-speech) without rebuilds. The choice is per
#   pipeline, not global - useful when you want one satellite to use
#   Kokoro and another to keep using F5.
#   Hostnames resolve from inside HA's Core container because we point
#   HAOS's Supervisor CoreDNS at skaia's unbound (`ha dns options
#   --servers dns://192.168.0.160` on the HA Yellow). Existing entries
#   created back when DNS didn't resolve still hold IP literals - safe
#   to leave, or reconfigure to FQDNs for clarity.
# - Atom Echo voice satellite (m5stack-atom-echo-54d358) and any future
#   wake-word satellites; HA brokers their audio to STT and pulls
#   synthesized audio from TTS, then plays it back on the satellite.
#
# Choices - STT (faster-whisper):
# - Model: distil-large-v3. Distilled English-only large model, ~1.5 GB
#   on disk. distil-medium.en was good enough on long utterances but
#   misheard short voice commands more often than we'd like; large-v3
#   is what HA's official add-on uses by default for voice satellites.
# - HF_TOKEN: piped in via systemd EnvironmentFile (ExecStartPre below).
#   faster-whisper fetches from the HF Hub on first run; without the
#   token we get rate-limit warnings in the journal.
# - Device: cuda. We override the upstream wyoming-faster-whisper package
#   so ctranslate2 is built with WITH_CUDA=ON and cuDNN, then point the
#   service at the 4090. Real-world impact: a 15s utterance that took ~6s
#   on CPU now transcribes well under a second (~30-50x realtime). The
#   NixOS module already wires up the right /dev/nvidia* DeviceAllow
#   entries when device is set to "cuda", so no extra plumbing here.
# - Beam size: 1. Greedy decoding; faster, accuracy difference negligible
#   on short utterances.
#
# Models we tried and rolled back from (kept here so we don't reach for
# them again without remembering why):
# - sherpa-onnx + Parakeet TDT 0.6B v3 (INT8): on paper 2026's leader
#   for English short-utterance latency (~6.3% WER vs ~7.5% for
#   distil-large-v3). In practice, on this hardware/satellite combo it
#   was a lateral move at best - similar perceived latency, similar or
#   worse perceived accuracy on the kinds of short commands we throw
#   at HA. Not worth the loss of the CUDA path. The wyoming-faster-
#   whisper sherpa handler also hardcodes provider="cpu", so we couldn't
#   put it on the GPU even if we wanted to without patching.
#
# Models we'd need real plumbing for, not a config flip:
# - NVIDIA Canary-Qwen 2.5B (currently top of the Open ASR leaderboard
#   for English, ~5.6% WER). Requires the full NVIDIA NeMo toolkit
#   (nemo.collections.speechlm2.models.SALM); none of wyoming-faster-
#   whisper's backends can load it. To use it we'd need a NeMo-backed
#   Python service plus a Wyoming bridge in the shape of wyoming-f5-tts.
#   Worth the lift only if STT accuracy ever blocks us.
# - Whisper Large V3 Turbo: faster-whisper supports it via model="turbo",
#   but multilingual; for our English-only traffic distil-large-v3 wins
#   on size and is at parity on latency.
#
# End-of-speech detection lives on the satellite side as the `Finished
# speaking detection` select entity in HA. Default value waits ~5s of
# trailing silence before stopping the recording, which is the single
# biggest source of voice loop latency. Recommended setting per device:
# - HA Voice PE (voice-1): `relaxed`. Has hardware AEC + decent VAD.
#   `aggressive` clipped utterances with natural hesitations like
#   "uh, what time is it?" mid-sentence; `relaxed` keeps the recording
#   open just long enough without that.
# - Atom Echo: `aggressive` if you must use it; the hardware VAD is
#   poor enough that the default 5s silence ceiling is what actually
#   ends most recordings.
# Not configurable from Nix because it's stored in HA's entity
# registry, not in the satellite firmware.
#
# Choices - TTS (F5-TTS proxy):
# - The actual neural TTS lives in tts.nix as the f5-tts Docker container
#   on 127.0.0.1:8880 (also exposed via nginx at tts.home.arpa). This
#   module just runs a thin Python translator that speaks Wyoming on the
#   wire and HTTP+streaming-PCM to F5-TTS. Source:
#   assets/wyoming-f5-tts.py.
# - We talk to F5-TTS over loopback, not via nginx, so we skip a
#   reverse-proxy hop and avoid getting mixed up in the LAN rate limits.
# - Voice list is hardcoded ("nature") because we currently only ship one
#   reference voice. Adding voices means dropping a {name}.wav + .txt into
#   /var/lib/tts/voices and bumping the --voices flag below.
# - Soft dependency on docker-tts.service: we 'after' but not 'requires'
#   it. If F5-TTS is down, the wrapper still answers Describe and will
#   surface HTTP errors as silent (empty) audio, which lets HA fail fast
#   instead of hanging the satellite.
#
# Choices - TTS (Kokoro proxy, a/b candidate):
# - Same shape as the F5 proxy: thin Python translator, Wyoming on one
#   side, OpenAI-compatible /v1/audio/speech (response_format=pcm) on
#   the other. Source: assets/wyoming-kokoro.py. Backing container in
#   hosts/skaia/kokoro.nix on 127.0.0.1:8881.
# - Why side-by-side instead of replacing F5: F5 has expressive prosody
#   but no text normalization frontend (turns "11:39" into "eleventeen
#   thirty-nine" because it phonemes the literal characters). Kokoro
#   uses misaki[en], which normalizes numbers/dates/times before
#   phonemizing. Running both lets us A/B in HA without rebuilds.
# - Voices: ~50 ship with Kokoro; we advertise a curated handful via
#   --voices. Default af_heart is the canonical Kokoro demo voice.
#   Add or rotate by editing the --voices flag below; no on-disk
#   changes needed (voice tensors live in the container image).
# - Soft dependency on docker-kokoro.service: same pattern as F5.
#
# Future additions in this file:
# - openWakeWord server, IFF we decide to do wake-word centrally rather
#   than on-device. Atom Echo currently does it on-device; not needed.

{ pkgs, ... }:

let
  wyomingF5Tts = pkgs.writeText "wyoming-f5-tts.py"
    (builtins.readFile ../../assets/wyoming-f5-tts.py);

  wyomingKokoro = pkgs.writeText "wyoming-kokoro.py"
    (builtins.readFile ../../assets/wyoming-kokoro.py);

  # Shared Python env for the Wyoming bridges. Both scripts only need
  # wyoming + httpx; using one env keeps the closure smaller.
  wyomingTtsEnv = pkgs.python3.withPackages (ps: [
    ps.wyoming
    ps.httpx
  ]);

  # CUDA-enabled wyoming-faster-whisper. We override the C++ ctranslate2
  # to be built with cuBLAS/cuDNN, scope that into the python package set,
  # then re-resolve wyoming-faster-whisper against the CUDA python set.
  # faster-whisper picks up the CUDA ctranslate2 transitively.
  ctranslate2Cuda = pkgs.ctranslate2.override { withCUDA = true; };
  python3PackagesCuda = pkgs.python3Packages.overrideScope (_: pyPrev: {
    ctranslate2 = pyPrev.ctranslate2.override {
      ctranslate2-cpp = ctranslate2Cuda;
    };
  });
  wyomingFasterWhisperCuda = pkgs.wyoming-faster-whisper.override {
    python3Packages = python3PackagesCuda;
  };

  # Use the existing huggingface-token secret to authenticate model
  # downloads from the HF Hub. Otherwise the service hits anonymous rate
  # limits (visible as warnings in the journal). Only matters for the
  # initial download of a model and any subsequent --model swaps.
  hfTokenFile = "/etc/nixos/secrets/huggingface-token-2025-12-14";

  prepWyomingFasterWhisperEnv = pkgs.writeShellScript
    "wyoming-faster-whisper-prep-env" ''
    set -euo pipefail
    umask 077
    install -d -m 0700 -o root -g root /run/wyoming-faster-whisper
    if [ -r ${hfTokenFile} ]; then
      printf 'HF_TOKEN=%s\n' "$(cat ${hfTokenFile})" \
        > /run/wyoming-faster-whisper/env
    else
      : > /run/wyoming-faster-whisper/env
    fi
    chmod 0600 /run/wyoming-faster-whisper/env
    chown root:root /run/wyoming-faster-whisper/env
  '';
in
{
  services.wyoming.faster-whisper = {
    package = wyomingFasterWhisperCuda;
    servers.default = {
      enable = true;
      uri = "tcp://0.0.0.0:10300";
      model = "distil-large-v3";
      language = "en";
      device = "cuda";
      beamSize = 1;
    };
  };

  # Pipe HF_TOKEN into the upstream service. systemd reads EnvironmentFile
  # as root before sandboxing is applied, so the file is mode 0600
  # root-owned and the service's DynamicUser identity never needs direct
  # access to it. The '+' prefix on ExecStartPre runs it as root,
  # bypassing the unit's User=/sandboxing for that step only.
  systemd.services = {
    wyoming-faster-whisper-default = {
      serviceConfig = {
        EnvironmentFile = "-/run/wyoming-faster-whisper/env";
        ExecStartPre = [ "+${prepWyomingFasterWhisperEnv}" ];
      };
    };

    wyoming-f5-tts = {
      description = "Wyoming protocol bridge to local F5-TTS server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "docker-tts.service" ];

      serviceConfig = {
        ExecStart = ''
          ${wyomingTtsEnv}/bin/python3 ${wyomingF5Tts} \
            --uri tcp://0.0.0.0:10200 \
            --f5-url http://127.0.0.1:8880 \
            --voices nature \
            --default-voice nature \
            --log-level INFO
        '';
        Restart = "on-failure";
        RestartSec = "5s";

        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };

    wyoming-kokoro = {
      description = "Wyoming protocol bridge to local Kokoro-FastAPI server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" "docker-kokoro.service" ];

      serviceConfig = {
        ExecStart = ''
          ${wyomingTtsEnv}/bin/python3 ${wyomingKokoro} \
            --uri tcp://0.0.0.0:10210 \
            --kokoro-url http://127.0.0.1:8881 \
            --voices af_heart,af_bella,af_sarah,am_michael,am_adam,bf_emma \
            --default-voice af_heart \
            --log-level INFO
        '';
        Restart = "on-failure";
        RestartSec = "5s";

        DynamicUser = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        RestrictNamespaces = true;
        RestrictRealtime = true;
        LockPersonality = true;
        MemoryDenyWriteExecute = true;
        SystemCallArchitectures = "native";
      };
    };
  };

  # Wyoming protocol - HA Yellow needs to reach STT and TTS on the LAN.
  networking.firewall.allowedTCPPorts = [
    10200 # F5-TTS Wyoming bridge
    10210 # Kokoro Wyoming bridge
    10300 # faster-whisper STT
  ];
}

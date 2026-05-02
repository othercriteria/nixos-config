# Voice assistant server-side stack on skaia.
#
# Currently provides:
# - Wyoming faster-whisper STT server on tcp://skaia.home.arpa:10300
# - Wyoming F5-TTS proxy           on tcp://skaia.home.arpa:10200
#
# Used by:
# - Home Assistant's Wyoming integration (Settings -> Devices & Services ->
#   Add -> Wyoming Protocol). Add one entry per service:
#     STT: 192.168.0.160:10300   (skaia.home.arpa from inside the HA addon
#                                 container does not resolve; use the IP)
#     TTS: 192.168.0.160:10200
# - Atom Echo voice satellite (m5stack-atom-echo-54d358) and any future
#   wake-word satellites; HA brokers their audio to STT and pulls
#   synthesized audio from TTS, then plays it back on the satellite.
#
# Choices - STT (faster-whisper):
# - Model: distil-medium.en. Distilled English-only, uncompressed: smaller
#   and faster than medium-int8 with comparable accuracy on conversational
#   English. Plenty for short voice commands. ~750 MB on disk.
# - Device: cuda. We override the upstream wyoming-faster-whisper package
#   so ctranslate2 is built with WITH_CUDA=ON and cuDNN, then point the
#   service at the 4090. Real-world impact: a 15s utterance that took ~6s
#   on CPU now transcribes in well under a second (~30-50x realtime). The
#   NixOS module already wires up the right /dev/nvidia* DeviceAllow
#   entries when device is set to "cuda", so no extra plumbing here.
# - Beam size: 1. Greedy decoding; faster, accuracy difference negligible
#   on short utterances.
#
# End-of-speech detection lives on the satellite (Atom Echo) side as the
# `Finished speaking detection` select entity in HA. Default value waits
# ~5s of trailing silence before stopping the recording, which is the
# single biggest source of voice loop latency. Set to `aggressive` in HA
# UI for snappier round trips. Not configurable from Nix because it's
# stored in HA's entity registry, not in the ESPHome firmware.
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
# Future additions in this file:
# - openWakeWord server, IFF we decide to do wake-word centrally rather
#   than on-device. Atom Echo currently does it on-device; not needed.

{ pkgs, ... }:

let
  wyomingF5Tts = pkgs.writeText "wyoming-f5-tts.py"
    (builtins.readFile ../../assets/wyoming-f5-tts.py);

  wyomingF5TtsEnv = pkgs.python3.withPackages (ps: [
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
in
{
  services.wyoming.faster-whisper = {
    package = wyomingFasterWhisperCuda;
    servers.default = {
      enable = true;
      uri = "tcp://0.0.0.0:10300";
      model = "distil-medium.en";
      language = "en";
      device = "cuda";
      beamSize = 1;
    };
  };

  systemd.services.wyoming-f5-tts = {
    description = "Wyoming protocol bridge to local F5-TTS server";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" "docker-tts.service" ];

    serviceConfig = {
      ExecStart = ''
        ${wyomingF5TtsEnv}/bin/python3 ${wyomingF5Tts} \
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

  # Wyoming protocol - HA Yellow needs to reach STT and TTS on the LAN.
  networking.firewall.allowedTCPPorts = [
    10200 # F5-TTS Wyoming bridge
    10300 # faster-whisper STT
  ];
}

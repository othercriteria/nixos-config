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
# - Device: cpu. faster-whisper on a modern x86 CPU (skaia: Ryzen 9 7950X)
#   runs roughly 5-10x real time on this model, so 1-3 second utterances
#   transcribe in ~150-500 ms. CUDA would be ~50x but pulling in a
#   CUDA-built CTranslate2 / faster-whisper through nixpkgs is fiddly.
#   Revisit if observed latency hurts.
# - Beam size: 1. Greedy decoding; faster, accuracy difference negligible
#   on short utterances.
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
in
{
  services.wyoming.faster-whisper.servers.default = {
    enable = true;
    uri = "tcp://0.0.0.0:10300";
    model = "distil-medium.en";
    language = "en";
    device = "cpu";
    beamSize = 1;
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

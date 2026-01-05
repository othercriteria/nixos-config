{ config, lib, pkgs, ... }:

# Self-hosted WebRTC streaming failover using SRS (Simple Realtime Server)
#
# Architecture:
#   OBS --WHIP--> Nginx (TLS) --> Auth Service --> SRS container --> Viewers
#
# Security:
#   WHIP publishing requires a bearer token stored in:
#   /etc/nixos/secrets/srs-whip-bearer-token
#
# Endpoints:
#   - Viewer: https://stream.valueof.info/ (auto-connecting player)
#   - WHIP ingest: https://stream.valueof.info/rtc/v1/whip/?app=live&stream=main
#
# OBS Configuration:
#   Settings > Stream > Service: WHIP
#   Server: https://stream.valueof.info/rtc/v1/whip/?app=live&stream=main
#   Bearer Token: <contents of /etc/nixos/secrets/srs-whip-bearer-token>

let
  # Using DNS name as candidate allows dynamic IP changes to be handled
  # gracefully - SRS resolves at connection time. Firefox may have issues
  # with DNS candidates (prefers IP), but Chrome/Edge/Safari work well.
  srsCandidate = "stream.valueof.info";

  # Path to the bearer token secret (managed via git-secret)
  bearerTokenFile = "/etc/nixos/secrets/srs-whip-bearer-token";

  # Simple bearer token auth service using Python
  # Reads expected token from file, compares against Authorization header
  # Returns 200 if valid, 401 if invalid
  srsAuthService = pkgs.writeScript "srs-auth-service" ''
    #!${pkgs.python3}/bin/python3
    import http.server
    import os

    TOKEN_FILE = os.environ.get("CREDENTIALS_DIRECTORY", "") + "/bearer-token"

    with open(TOKEN_FILE) as f:
        EXPECTED_TOKEN = f.read().strip()

    class AuthHandler(http.server.BaseHTTPRequestHandler):
        def do_GET(self):
            auth = self.headers.get("Authorization", "")
            if auth.startswith("Bearer "):
                provided = auth[7:].strip()
            else:
                provided = ""

            if provided == EXPECTED_TOKEN and provided:
                self.send_response(200)
            else:
                self.send_response(401)
            self.end_headers()

        def log_message(self, format, *args):
            pass  # Suppress logging

    server = http.server.HTTPServer(("127.0.0.1", 8086), AuthHandler)
    server.serve_forever()
  '';

  # Simple WHEP player page - auto-connects to the stream
  playerPage = pkgs.writeTextFile {
    name = "stream-player";
    destination = "/index.html";
    text = builtins.readFile ../../assets/stream-player.html;
  };

  srsConfig = pkgs.writeText "srs.conf" ''
    listen 1935;
    max_connections 100;
    daemon off;

    http_api {
      enabled on;
      listen 1985;
      # Allow cross-origin for web players
      crossdomain on;
    }

    http_server {
      enabled on;
      listen 8080;
      dir ./objs/nginx/html;
      # Serves demo players at /players/
    }

    rtc_server {
      enabled on;
      listen 8000;
      # Use DNS name for dynamic IP resilience
      candidate ${srsCandidate};
    }

    vhost __defaultVhost__ {
      rtc {
        enabled on;
        # Allow WHIP publishing (OBS ingest)
        rtc_to_rtmp off;
      }

      http_remux {
        enabled on;
        mount [vhost]/[app]/[stream].flv;
      }
    }
  '';
in
{
  # COLD START: Configure router to forward UDP 8000 to skaia for WebRTC media.
  # Also ensure stream.valueof.info A record points to the public IP.
  # See docs/COLD-START.md for details.

  # Use Docker backend (already configured on skaia)
  virtualisation.oci-containers.backend = "docker";

  # SRS container for WebRTC streaming
  virtualisation.oci-containers.containers.srs = {
    image = "ossrs/srs:5";
    ports = [
      "127.0.0.1:1935:1935" # RTMP ingest - localhost only (for obs-multi-rtmp)
      "127.0.0.1:1985:1985" # HTTP API (WHIP/WHEP signaling) - localhost only
      "127.0.0.1:8080:8080" # HTTP server (demo players) - localhost only
      "8000:8000/udp" # WebRTC media - must be public
    ];
    volumes = [
      "${srsConfig}:/usr/local/srs/conf/srs.conf:ro"
    ];
    # Note: NixOS oci-containers uses --rm by default, so systemd handles
    # restarts rather than Docker's --restart policy
  };

  # Bearer token auth service for WHIP publishing
  systemd.services.srs-auth = {
    description = "SRS WHIP Bearer Token Auth Service";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      ExecStart = "${srsAuthService}";
      Restart = "always";
      RestartSec = "5s";
      DynamicUser = true;
      # Pass the secret via systemd credentials (secure, no filesystem exposure)
      LoadCredential = "bearer-token:${bearerTokenFile}";
    };
  };

  # Nginx reverse proxy with TLS termination
  services.nginx.virtualHosts."stream.valueof.info" = {
    forceSSL = true;
    enableACME = true;

    locations = {
      # Internal auth endpoint for WHIP bearer token validation
      "= /auth" = {
        proxyPass = "http://127.0.0.1:8086";
        extraConfig = ''
          internal;
          proxy_pass_request_body off;
          proxy_set_header Content-Length "";
          proxy_set_header X-Original-URI $request_uri;
          proxy_set_header Authorization $http_authorization;
        '';
      };

      # WHIP ingest - requires bearer token authentication
      "/rtc/v1/whip/" = {
        proxyPass = "http://127.0.0.1:1985";
        extraConfig = ''
          auth_request /auth;
          auth_request_set $auth_status $upstream_status;

          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };

      # WHEP playback and other RTC endpoints - public access (viewers)
      "/rtc/" = {
        proxyPass = "http://127.0.0.1:1985";
        extraConfig = ''
          proxy_set_header Host $host;
          proxy_set_header X-Real-IP $remote_addr;
          proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
          proxy_set_header X-Forwarded-Proto $scheme;
        '';
      };

      # Root serves the auto-connecting player
      "/" = {
        root = playerPage;
        index = "index.html";
      };
    };

    extraConfig = ''
      # Security headers
      add_header Strict-Transport-Security "max-age=31536000" always;
      add_header X-Content-Type-Options "nosniff" always;
    '';
  };

  # Open UDP port for WebRTC media traffic
  networking.firewall.allowedUDPPorts = [
    8000 # SRS WebRTC media (ICE/DTLS/SRTP)
  ];

  # Future: coturn integration
  # When adding TURN server support:
  # 1. Enable services.coturn with appropriate realm and credentials
  # 2. Update srsConfig to include TURN server URLs
  # 3. Open coturn ports (3478 TCP/UDP, relay range)
  # See: https://ossrs.net/lts/en-us/docs/v5/doc/webrtc#coturn
}

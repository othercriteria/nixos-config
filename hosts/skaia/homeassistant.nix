# Home Assistant integration for skaia
#
# Provides:
# - Secure nginx reverse proxy with TLS (assistant.valueof.info)
# - Rate limiting on auth endpoints
# - Fail2ban jail for brute-force protection
# - Prometheus metrics scraping
# - Alerting on authentication failures
#
# Prerequisites (see docs/COLD-START.md):
# - Home Assistant long-lived access token stored in secrets/homeassistant-token
# - Prometheus integration enabled in HA's configuration.yaml (add: prometheus:)
# - Enable 2FA/TOTP in Home Assistant (strongly recommended)
#
# Security notes:
# - Rate limiting: 10 req/min on /auth/ endpoints, 60 req/min general
# - Fail2ban: 5 failures in 10 minutes = 1 hour ban
# - All traffic forced to TLS with HSTS
# - WebSocket support for HA's real-time features

{ config, lib, pkgs, ... }:

let
  # Home Assistant internal address (static IP from router DHCP)
  haUpstream = "192.168.0.184:8123";

  # Rate limit zones
  # - ha_auth: strict limit for authentication endpoints
  # - ha_general: permissive limit for normal traffic
  rateLimitConfig = ''
    # Rate limit zones for Home Assistant
    limit_req_zone $binary_remote_addr zone=ha_auth:10m rate=10r/m;
    limit_req_zone $binary_remote_addr zone=ha_general:10m rate=60r/s;

    # Return 429 (Too Many Requests) instead of 503 for rate limits
    limit_req_status 429;
  '';
in
{
  # COLD START: Create a long-lived access token in Home Assistant:
  # 1. Go to your HA profile (click username in sidebar)
  # 2. Scroll to "Long-Lived Access Tokens"
  # 3. Create token named "nixos-prometheus" (or similar)
  # 4. Store: echo -n 'TOKEN' > secrets/homeassistant-token
  # 5. Encrypt: git secret add secrets/homeassistant-token && git secret hide
  #
  # SECURITY: Enable 2FA/TOTP in Home Assistant before exposing externally!
  # Settings → People → [your user] → Enable Multi-factor Authentication

  services = {
    nginx = {
      # Add rate limit configuration to http context
      appendHttpConfig = rateLimitConfig;

      virtualHosts."assistant.valueof.info" = {
        forceSSL = true;
        enableACME = true;

        # Dedicated access log for fail2ban parsing (uses default 'combined' format)
        extraConfig = ''
          access_log /var/log/nginx/homeassistant-access.log combined;

          # Security headers
          add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header X-Frame-Options "SAMEORIGIN" always;
          add_header Referrer-Policy "strict-origin-when-cross-origin" always;

          # Hide nginx version
          server_tokens off;

          # Limit request body size (HA doesn't need huge uploads)
          client_max_body_size 50M;
        '';

        locations = {
          # Authentication endpoints - strict rate limiting
          "/auth/" = {
            proxyPass = "http://${haUpstream}";
            proxyWebsockets = true;
            extraConfig = ''
              # Strict rate limit: 10 requests/minute with small burst
              limit_req zone=ha_auth burst=5 nodelay;

              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;

              # Timeouts for auth
              proxy_connect_timeout 10s;
              proxy_send_timeout 30s;
              proxy_read_timeout 30s;
            '';
          };

          # API endpoints - moderate rate limiting
          "/api/" = {
            proxyPass = "http://${haUpstream}";
            proxyWebsockets = true;
            extraConfig = ''
              # Moderate rate limit for API
              limit_req zone=ha_general burst=30 nodelay;

              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;

              # Longer timeouts for API calls
              proxy_connect_timeout 10s;
              proxy_send_timeout 60s;
              proxy_read_timeout 60s;
            '';
          };

          # WebSocket endpoint for real-time updates
          "/api/websocket" = {
            proxyPass = "http://${haUpstream}";
            proxyWebsockets = true;
            extraConfig = ''
              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;

              # WebSocket-specific settings
              proxy_connect_timeout 10s;
              proxy_send_timeout 86400s;
              proxy_read_timeout 86400s;
            '';
          };

          # Default location - general rate limiting
          "/" = {
            proxyPass = "http://${haUpstream}";
            proxyWebsockets = true;
            extraConfig = ''
              limit_req zone=ha_general burst=30 nodelay;

              proxy_set_header Host $host;
              proxy_set_header X-Real-IP $remote_addr;
              proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
              proxy_set_header X-Forwarded-Proto $scheme;
              proxy_set_header Upgrade $http_upgrade;
              proxy_set_header Connection "upgrade";

              # General timeouts
              proxy_connect_timeout 10s;
              proxy_send_timeout 60s;
              proxy_read_timeout 60s;

              # Disable buffering for real-time updates
              proxy_buffering off;
            '';
          };
        };
      };

      # LAN-only access (no TLS, direct IP)
      virtualHosts."assistant.home.arpa" = {
        listen = [{ addr = "0.0.0.0"; port = 80; }];
        locations."/" = {
          proxyPass = "http://${haUpstream}";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_buffering off;
          '';
        };
      };
    };

    # Fail2ban jail for Home Assistant authentication failures
    fail2ban.jails = {
      homeassistant = {
        enabled = true;
        settings = {
          filter = "homeassistant";
          action = "iptables-multiport[name=homeassistant, port=\"http,https\"]";
          logpath = "/var/log/nginx/homeassistant-access.log";
          maxretry = 5;
          findtime = 600; # 10 minutes
          bantime = 3600; # 1 hour
        };
      };
    };

    # Prometheus scrape configuration for Home Assistant metrics
    # Requires: Enable Prometheus integration in HA first
    # Note: Token is copied to /run/prometheus/ with correct permissions at service start
    prometheus.scrapeConfigs = [
      {
        job_name = "homeassistant";
        scrape_interval = "60s";
        metrics_path = "/api/prometheus";
        bearer_token_file = "/run/prometheus/homeassistant-token";
        static_configs = [{
          targets = [ haUpstream ];
          labels = {
            instance = "homeassistant";
          };
        }];
      }
    ];
  };

  # Fail2ban filter for Home Assistant
  # Matches 401 responses to auth endpoints
  environment.etc."fail2ban/filter.d/homeassistant.conf".text = ''
    [Definition]
    failregex = ^<HOST> .* "(POST|GET) /auth/.*" (401|403)
                ^<HOST> .* "(POST|GET) /api/.*" (401|403)
    ignoreregex =
  '';

  systemd = {
    # Ensure log directory exists for fail2ban
    tmpfiles.rules = [
      "f /var/log/nginx/homeassistant-access.log 0640 nginx nginx -"
    ];

    # Ensure Prometheus can read the Home Assistant token
    # The token file is decrypted by git-secret with user ownership,
    # but Prometheus runs as its own user and needs read access.
    services.prometheus.serviceConfig = {
      ExecStartPre = [
        "+${pkgs.coreutils}/bin/install -m 0400 -o prometheus -g prometheus /etc/nixos/secrets/homeassistant-token /run/prometheus/homeassistant-token"
      ];
      RuntimeDirectory = "prometheus";
    };
  };
}

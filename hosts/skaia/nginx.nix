{
  config,
  lib,
  pkgs,
  ...
}:

let
  # Path to the Basic Auth htpasswd file used by the trivia vhost. Created
  # via git-secret; see docs/runbooks/trivia-setup.md.
  triviaHtpasswd = "/etc/nixos/secrets/trivia-htpasswd";

  # The apex page. Static files checked in under assets/valueof-info/ and
  # copied into the store, so the page ships with the system closure; the
  # vhost's CSP is default-src 'self', which is why styling is a file and
  # not an inline <style> block.
  valueofInfoStatic = pkgs.runCommand "valueof-info-static" { } ''
    mkdir -p "$out"
    cp ${../../assets/valueof-info/index.html} "$out/index.html"
    cp ${../../assets/valueof-info/site.css} "$out/site.css"
  '';
in
{
  # COLD START: Configure the TP-Link router to forward TCP 80 and 443 to skaia
  # before expecting public HTTP(S) traffic to reach this host. Steps are
  # documented in docs/COLD-START.md.
  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    recommendedGzipSettings = true;
    recommendedOptimisation = true;

    # Rate-limit zones used by trivia.valueof.info. Defined at http{} scope
    # so they can be applied per-location below. Sized for one trivia
    # event's worth of contestants; nginx tracks ~16k IPs per MB. Note:
    # `limit_req_status 429;` is already declared once at http{} scope by
    # hosts/skaia/homeassistant.nix; nginx forbids it from being repeated,
    # so we don't redeclare it here. The 429 status applies to all zones.
    appendHttpConfig = ''
      limit_req_zone $binary_remote_addr zone=trivia_req:10m rate=10r/s;
      limit_conn_zone $binary_remote_addr zone=trivia_conn:10m;
    '';

    virtualHosts = {
      "valueof.info" = {
        forceSSL = true;
        enableACME = true;
        root = valueofInfoStatic;
        locations = {
          "/" = {
            index = "index.html";
          };

          # The book page. A path under this vhost rather than its own
          # service, per the deployment contract in the book repo's
          # planning/site-handoff.md. Content is published by
          # modules/baltic-site, which swaps the symlink atomically.
          #
          # The trailing slash is the ruled path form, so send the bare
          # path to it instead of letting it fall through to the apex root.
          "= /the-baltic-approaches" = {
            return = "301 /the-baltic-approaches/";
          };

          "/the-baltic-approaches/" = {
            alias = "${config.custom.balticSite.docRoot}/";
            index = "index.html";
            extraConfig = ''
              # The page fetches nothing off-origin and executes nothing
              # inline: its atlas data rides in a type="application/json"
              # block, which CSP does not treat as executable content.
              add_header Content-Security-Policy "default-src 'none'; img-src 'self'; style-src 'self'; script-src 'self'" always;
              add_header Referrer-Policy "no-referrer" always;
              add_header Strict-Transport-Security "max-age=31536000" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header X-Frame-Options "DENY" always;

              # UTF-8 on every text type the contract names. nginx's
              # default charset_types omits text/css, and llms.txt is
              # served from here as text/plain. text/html is always
              # charset-tagged and nginx warns if it is listed again.
              #
              # Both JavaScript types are listed because nginx's mime.types
              # now maps .js to text/javascript; with only the contract's
              # application/javascript, site.js went out untagged and its
              # middle dots decoded correctly only by inheriting the
              # document's encoding.
              charset utf-8;
              charset_types text/css text/plain text/javascript application/javascript;
            '';
          };

          # The résumé page, same shape as the book page: published by
          # modules/resume-site from github:othercriteria/resume, served as a
          # path under the apex so it needs no DNS record or certificate of
          # its own. The location redeclares every header because nginx's
          # add_header inheritance is all-or-nothing per level.
          "= /daniel-klein-resume" = {
            return = "301 /daniel-klein-resume/";
          };

          "/daniel-klein-resume/" = {
            alias = "${config.custom.resumeSite.docRoot}/";
            index = "index.html";
            extraConfig = ''
              add_header Content-Security-Policy "default-src 'none'; style-src 'self'" always;
              add_header Referrer-Policy "no-referrer" always;
              add_header Strict-Transport-Security "max-age=31536000" always;
              add_header X-Content-Type-Options "nosniff" always;
              add_header X-Frame-Options "DENY" always;

              charset utf-8;
              charset_types text/css text/plain;
            '';
          };
        };

        extraConfig = ''
          add_header Content-Security-Policy "default-src 'self'" always;
          add_header Referrer-Policy "no-referrer" always;
          add_header Strict-Transport-Security "max-age=31536000" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header X-Frame-Options "DENY" always;
        '';
      };

      "teleport.valueof.info" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "https://127.0.0.1:3080";
          proxyWebsockets = true;
          extraConfig = ''
            proxy_ssl_verify off;
            proxy_ssl_server_name on;
          '';
        };
        extraConfig = ''
          add_header Strict-Transport-Security "max-age=31536000" always;
        '';
      };

      "urbit.valueof.info" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://hive.home.arpa:8080";
          # services.nginx.recommendedProxySettings = true already injects
          # Host/X-Real-IP/X-Forwarded-* here. Re-declaring them duplicates
          # the headers, which strict HTTP parsers (e.g. aiohttp >= 3.10)
          # reject with 400 "Duplicate 'Host' header found." See the same
          # note in hosts/skaia/homeassistant.nix.
          extraConfig = ''
            chunked_transfer_encoding off;
            proxy_buffering off;
            proxy_cache off;
          '';
        };
      };

      "stiletto.valueof.info" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          # Use raw config instead of proxyPass to avoid recommendedProxySettings
          # overwriting our custom Host header needed for cluster ingress routing
          extraConfig = ''
            proxy_pass http://192.168.0.220;
            proxy_http_version 1.1;
            proxy_set_header Host stiletto-lite.veil.home.arpa;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_set_header X-Forwarded-Host $host;
          '';
        };
        extraConfig = ''
          add_header Strict-Transport-Security "max-age=31536000" always;
        '';
      };

      # ntfy.sh push notification server (public)
      # Mobile apps and external services can publish/subscribe to topics
      "ntfy.valueof.info" = {
        forceSSL = true;
        enableACME = true;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8090";
          proxyWebsockets = true;
          extraConfig = ''
            # ntfy official proxy example: disable buffering so SSE /
            # long-poll / iOS poll_request fetches are not held in nginx.
            # Timeouts at 3m match upstream; attachments can be large.
            proxy_buffering off;
            proxy_request_buffering off;
            proxy_connect_timeout 3m;
            proxy_send_timeout 3m;
            proxy_read_timeout 3m;
            client_max_body_size 50M;
          '';
        };
        extraConfig = ''
          add_header Strict-Transport-Security "max-age=31536000" always;
        '';
      };

      # Trivia drip-release file server (public, Basic-Auth gated).
      # Backing service defined in modules/trivia.nix; see also
      # docs/runbooks/trivia-setup.md for the htpasswd setup. The
      # credential is shared with all contestants out-of-band (e.g.
      # alongside the event invite); the URL is recoverable from
      # Certificate Transparency logs, so Basic Auth is the real
      # authentication boundary here.
      #
      # Between events custom.trivia.enable is false (see
      # hosts/skaia/default.nix). The vhost stays defined so any stray
      # hit is Basic-Auth 401'd before the absent upstream matters.
      # TLS/ACME follow enable: the public name is NXDOMAIN when
      # parked, and Let's Encrypt was failing the order unit daily.
      "trivia.valueof.info" = {
        forceSSL = config.custom.trivia.enable;
        enableACME = config.custom.trivia.enable;
        basicAuthFile = triviaHtpasswd;
        locations."/" = {
          proxyPass = "http://127.0.0.1:8765";
          extraConfig = ''
            # Range requests get streamed straight through so MP3 seek
            # and resumable downloads work without buffering in nginx.
            proxy_buffering off;
            proxy_read_timeout 120s;

            limit_req zone=trivia_req burst=30 nodelay;
            limit_conn trivia_conn 4;
          '';
        };
        extraConfig = ''
          # No uploads here; the only legitimate verb is GET. 1 KB caps the
          # request body so malformed clients/scanners can't ship surprises
          # into the app. client_*_timeout live at server scope (nginx
          # forbids them inside a location block).
          client_max_body_size 1k;
          client_body_timeout 10s;
          client_header_timeout 10s;

          add_header Strict-Transport-Security "max-age=31536000" always;
          add_header X-Content-Type-Options "nosniff" always;
          add_header Referrer-Policy "no-referrer" always;
          add_header X-Robots-Tag "noindex, nofollow" always;
        '';
      };

      # Private Forgejo web UI (LAN only for MVP)
      "forgejo.home.arpa" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = 80;
          }
        ];
        locations."/" = {
          # Use raw proxy config so the forwarded Host header stays as
          # forgejo.home.arpa. The proxyPass helper combined with recommended
          # proxy settings can rewrite Host to the upstream address, which
          # Forgejo then rejects because it does not match ROOT_URL.
          extraConfig = ''
            proxy_pass http://127.0.0.1:3044;
            proxy_http_version 1.1;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            client_max_body_size 1G;
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
          '';
        };
      };

      # Netdata real-time monitoring (LAN only)
      "netdata.home.arpa" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = 80;
          }
        ];
        locations."/" = {
          proxyPass = "http://127.0.0.1:19999";
          proxyWebsockets = true;
          # recommendedProxySettings + proxyWebsockets already inject
          # Host/X-Forwarded-*/Upgrade/Connection. Don't redeclare here.
        };
      };

      # Harmonia Nix binary cache (LAN only)
      "cache.home.arpa" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = 80;
          }
        ];
        locations."/" = {
          proxyPass = "http://127.0.0.1:5380";
          # recommendedProxySettings already injects Host/X-Forwarded-*.
        };
      };

      # Ollama LLM API (LAN only)
      # OpenAI-compatible endpoint at /v1/chat/completions for MCP integration
      "ollama.home.arpa" = {
        listen = [
          {
            addr = "0.0.0.0";
            port = 80;
          }
        ];
        locations."/" = {
          # Use raw config to avoid recommendedProxySettings overriding Host header
          # (Ollama rejects requests with Host != localhost for DNS rebinding protection)
          extraConfig = ''
            proxy_pass http://127.0.0.1:11434;
            proxy_http_version 1.1;
            proxy_set_header Host localhost;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            # Streaming: disable buffering for real-time token delivery
            proxy_buffering off;
            # Long inference: 10 minute timeout for large generations
            proxy_read_timeout 600s;
            proxy_send_timeout 600s;
            # Large context windows can produce big requests/responses
            client_max_body_size 100M;
          '';
        };
      };
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "othercriteria@gmail.com";
  };

  # `make reveal-secrets` and the workspace -> /etc/nixos sync leave the
  # htpasswd file as 0600 owned by the invoking user. nginx workers run as
  # the `nginx` user and need read access to validate Basic Auth challenges.
  #
  # We do this in an activation script (rather than tmpfiles or nginx's
  # preStart) because:
  # - tmpfiles' `z` rule only re-fires when tmpfiles config changes, so a
  #   "edit secret only" deploy leaves the file with workspace perms.
  # - nginx.service's preStart inherits the unit's SystemCallFilter, which
  #   excludes @chown -- chown(2) gets SIGSYS-killed there.
  # Activation scripts run as root, outside any sandbox, on every switch
  # and every boot. Tolerant of the file's absence so a fresh deploy
  # before secrets have been revealed doesn't crash activation.
  system.activationScripts.trivia-htpasswd-perms = ''
    if [ -f ${triviaHtpasswd} ]; then
      chown root:nginx ${triviaHtpasswd}
      chmod 0640 ${triviaHtpasswd}
    fi
  '';

  # Ensure nginx only starts or reloads once DNS (Unbound) is available so
  # upstreams that rely on home.arpa resolution don't fail config tests.
  systemd.services.nginx = {
    after = lib.mkAfter [ "unbound.service" ];
    requires = lib.mkAfter [ "unbound.service" ];
  };
}

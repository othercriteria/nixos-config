{ config, lib, pkgs, ... }:

let
  valueofInfoStatic = pkgs.writeTextFile {
    name = "valueof-info-index";
    destination = "/index.html";
    text = ''
      <!DOCTYPE html>
      <html lang="en">
        <head>
          <meta charset="utf-8" />
          <title>valueof.info</title>
          <meta http-equiv="X-UA-Compatible" content="IE=edge" />
          <meta name="viewport" content="width=device-width, initial-scale=1.0" />
          <style>
            body {
              font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI",
                sans-serif;
              margin: 0;
              min-height: 100vh;
              display: grid;
              place-items: center;
              background: #0d1117;
              color: #d0d7de;
            }
            main {
              text-align: center;
              padding: 3rem 2rem;
              border: 1px solid rgba(210, 218, 226, 0.1);
              border-radius: 12px;
              background: rgba(13, 17, 23, 0.75);
              max-width: 45ch;
            }
            h1 {
              font-weight: 600;
              margin-bottom: 1rem;
            }
            p {
              margin: 0.5rem 0 0;
              line-height: 1.5;
            }
          </style>
        </head>
        <body>
          <main>
            <h1>valueof.info</h1>
            <p>This site is intentionally minimal while ingress is being stood up.</p>
          </main>
        </body>
      </html>
    '';
  };
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

    virtualHosts = {
      "valueof.info" = {
        forceSSL = true;
        enableACME = true;
        root = valueofInfoStatic;
        locations."/" = {
          index = "index.html";
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
    };
  };

  security.acme = {
    acceptTerms = true;
    defaults.email = "othercriteria@gmail.com";
  };
}

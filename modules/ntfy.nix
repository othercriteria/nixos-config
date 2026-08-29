# ntfy.sh push notification server module
#
# Self-hosted ntfy instance for instant push notifications. Integrates with:
# - Prometheus Alertmanager (webhook receiver)
# - Home Assistant (REST notifications)
# - systemd services (curl-based alerts)
# - Mobile/desktop apps (ntfy.sh clients)
#
# Usage:
#   imports = [ ../../modules/ntfy.nix ];
#   custom.ntfy = {
#     enable = true;
#     baseUrl = "https://ntfy.valueof.info";
#     auth = {
#       enable = true;
#       passwordFile = "/etc/nixos/secrets/ntfy-password";
#     };
#   };

{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.custom.ntfy;

  # Alertmanager's webhook is a JSON blob. ntfy will run this Go template
  # over it when the publisher sets `?template=alertmanager`. Title is the
  # alert summary (what iOS shows on the lock screen); body is the
  # description. Stock ntfy alertmanager.yml also dumps receiver name,
  # RFC3339 timestamps, and Prometheus generator URLs, which are noise
  # on a phone.
  alertmanagerTemplateDir = pkgs.writeTextDir "alertmanager.yml" ''
    title: |
      {{- $a := first .alerts -}}
      {{- if eq .status "resolved" }}Resolved: {{ end -}}
      {{- with $a.annotations.summary }}{{ . }}{{ else }}{{ $a.labels.alertname }}{{ end }}
    message: |
      {{- range .alerts }}
      {{- with .annotations.description }}{{ . }}{{ else }}{{ .labels.alertname }} is {{ $.status }}{{ end }}
      {{- with .labels.severity }} [{{ . }}]{{ end }}
      {{ end -}}
  '';
in
{
  options.custom.ntfy = {
    enable = lib.mkEnableOption "ntfy.sh push notification server";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "HTTP port for ntfy server (internal).";
    };

    baseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://localhost:8090";
      description = ''
        Public base URL for ntfy. Used for attachment URLs and web UI.
        Set to your public URL (e.g., https://ntfy.valueof.info) when
        exposing via reverse proxy.
      '';
    };

    behindProxy = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether ntfy is behind a reverse proxy (trust X-Forwarded-For).";
    };

    cacheFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ntfy-sh/cache.db";
      description = "Path to the message cache database.";
    };

    cacheDuration = lib.mkOption {
      type = lib.types.str;
      default = "72h";
      description = "How long to keep messages in the cache.";
    };

    attachmentCacheDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/ntfy-sh/attachments";
      description = "Directory for attachment storage.";
    };

    attachmentTotalSizeLimit = lib.mkOption {
      type = lib.types.str;
      default = "1G";
      description = "Total size limit for all attachments.";
    };

    attachmentFileSizeLimit = lib.mkOption {
      type = lib.types.str;
      default = "50M";
      description = "Maximum size per attachment.";
    };

    upstreamBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://ntfy.sh";
      description = ''
        Upstream ntfy server used to fan out iOS poll_request messages
        through Firebase/APNs. Must be "https://ntfy.sh" (not this
        server) for timely iOS notifications. UnifiedPush on Android
        does not use this setting.
      '';
    };

    metricsPort = lib.mkOption {
      type = lib.types.port;
      default = 8091;
      description = ''
        Dedicated localhost port for the Prometheus /metrics endpoint.
        Kept off the public ntfy vhost so metrics are not Internet-facing.
      '';
    };

    auth = {
      enable = lib.mkEnableOption "authentication for ntfy";

      defaultAccess = lib.mkOption {
        type = lib.types.enum [
          "read-write"
          "read-only"
          "write-only"
          "deny-all"
        ];
        default = "deny-all";
        description = "Default access level for unauthenticated users.";
      };

      username = lib.mkOption {
        type = lib.types.str;
        default = "admin";
        description = "Username for the ntfy admin user.";
      };

      passwordFile = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = "Path to file containing the password for the admin user.";
      };
    };

    extraUsers = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            username = lib.mkOption {
              type = lib.types.str;
              description = "Username. Must match ntfy's accepted characters (alphanumerics, -, _).";
            };
            passwordFile = lib.mkOption {
              type = lib.types.str;
              description = "Path to a file containing the user's password.";
            };
            role = lib.mkOption {
              type = lib.types.enum [
                "admin"
                "user"
              ];
              default = "user";
              description = ''
                ntfy role. 'user' is subject to defaultAccess plus explicit
                grants; 'admin' has unrestricted access regardless of grants.
              '';
            };
            grants = lib.mkOption {
              type = lib.types.listOf (
                lib.types.submodule {
                  options = {
                    topic = lib.mkOption {
                      type = lib.types.str;
                      description = ''
                        Topic name. ntfy supports wildcards via '*' (e.g.
                        'veil-*' grants on all veil-prefixed topics).
                      '';
                    };
                    access = lib.mkOption {
                      type = lib.types.enum [
                        "read-write"
                        "read-only"
                        "write-only"
                        "deny-all"
                      ];
                      description = "Access level on this topic.";
                    };
                  };
                }
              );
              default = [ ];
              description = "Per-topic ACL grants applied via 'ntfy access'.";
            };
          };
        }
      );
      default = [ ];
      description = ''
        Additional, non-admin ntfy users with optional per-topic ACL
        grants. Provisioned by an ExecStartPre on ntfy-sh.service, which
        ensures the script runs under the same User= + DynamicUser= +
        StateDirectory bind mount as the main service. Idempotent:
        users are created on first run and have their password rewritten
        + ACLs reapplied on subsequent service starts.
      '';
    };
  };

  config = lib.mkIf cfg.enable (
    let
      # Credential IDs for systemd LoadCredential=. Each ID gets a file
      # at $CREDENTIALS_DIRECTORY/<id> in the running service, owned by
      # the service's (dynamic) UID with mode 0400. systemd reads the
      # source files as PID 1 (root), so we can leave the host-side
      # secrets at 0600 dlk:users.
      adminCredId = "admin-password";
      extraCredId = user: "extrauser-${user.username}-password";

      adminCredArg = lib.optional (
        cfg.auth.passwordFile != null
      ) "${adminCredId}:${cfg.auth.passwordFile}";
      extraCredArgs = map (u: "${extraCredId u}:${u.passwordFile}") cfg.extraUsers;

      # User-provisioning script, run as an ExecStartPre of
      # ntfy-sh.service. Embedding the provisioning in the main service
      # is deliberate: with DynamicUser=true + StateDirectory=ntfy-sh,
      # /var/lib/ntfy-sh is a private bind mount only visible inside
      # the service namespace, and the ephemeral UID for "ntfy-sh" is
      # only honored by units running as the same User=. A separate
      # oneshot would either run under the wrong UID or see the wrong
      # /var/lib/ntfy-sh contents.
      provisionUsers = pkgs.writeShellApplication {
        name = "ntfy-sh-provision-users";
        runtimeInputs = [
          pkgs.ntfy-sh
          pkgs.coreutils
          pkgs.gnugrep
        ];
        text = ''
          set -euo pipefail

          export NTFY_AUTH_FILE="/var/lib/ntfy-sh/user.db"

          if [ -z "''${CREDENTIALS_DIRECTORY:-}" ]; then
            echo "ntfy-sh-provision-users: CREDENTIALS_DIRECTORY not set" >&2
            exit 1
          fi

          ${lib.optionalString (cfg.auth.passwordFile != null) ''
            NTFY_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/${adminCredId}")
            export NTFY_PASSWORD
            if ! ntfy user list 2>/dev/null \
                | grep -q "^user ${cfg.auth.username}"; then
              echo "Creating ntfy admin user '${cfg.auth.username}'..."
              ntfy user add --role=admin ${cfg.auth.username}
            else
              echo "Updating admin user password..."
              ntfy user change-pass ${cfg.auth.username} || true
            fi
            unset NTFY_PASSWORD
          ''}

          ${lib.concatMapStrings (user: ''
            echo "Setting up ntfy user '${user.username}' (role=${user.role})..."
            if ! ntfy user list 2>/dev/null \
                | grep -q "^user ${user.username}"; then
              NTFY_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/${extraCredId user}") \
                ntfy user add --role=${user.role} ${user.username}
            else
              NTFY_PASSWORD=$(cat "$CREDENTIALS_DIRECTORY/${extraCredId user}") \
                ntfy user change-pass ${user.username} || true
            fi
            ${lib.concatMapStrings (grant: ''
              ntfy access ${user.username} '${grant.topic}' ${grant.access}
            '') user.grants}
          '') cfg.extraUsers}

          echo "ntfy user setup complete"
        '';
      };

      needsProvisioning = cfg.auth.enable && (cfg.auth.passwordFile != null || cfg.extraUsers != [ ]);
    in
    {
      services.ntfy-sh = {
        enable = true;
        settings = {
          listen-http = "127.0.0.1:${toString cfg.port}";
          base-url = cfg.baseUrl;
          behind-proxy = cfg.behindProxy;

          # Message cache
          cache-file = cfg.cacheFile;
          cache-duration = cfg.cacheDuration;

          # Attachments
          attachment-cache-dir = cfg.attachmentCacheDir;
          attachment-total-size-limit = cfg.attachmentTotalSizeLimit;
          attachment-file-size-limit = cfg.attachmentFileSizeLimit;

          # iOS instant notifications: every publish also POSTs a
          # poll_request (message id only) to this upstream, which fans
          # out FCM → APNs. The iOS app then fetches the real payload
          # from this server. See docs.ntfy.sh "iOS instant notifications".
          upstream-base-url = cfg.upstreamBaseUrl;

          # Prometheus metrics on localhost only (not the public vhost).
          metrics-listen-http = "127.0.0.1:${toString cfg.metricsPort}";

          # Custom Alertmanager webhook template (see alertmanagerTemplateDir).
          template-dir = "${alertmanagerTemplateDir}";

          # Logging
          log-level = "info";
        }
        // lib.optionalAttrs cfg.auth.enable {
          # Authentication
          auth-file = "/var/lib/ntfy-sh/user.db";
          auth-default-access = cfg.auth.defaultAccess;
        };
      };

      # Inject user provisioning into the main service's start sequence.
      # ExecStartPre runs in the same mount namespace and as the same
      # DynamicUser/User= as ExecStart, so it can write to user.db
      # under the right UID. State is converged on every service start.
      # LoadCredential= lets systemd (as root) stage each password file
      # into a tmpfs owned by the dynamic UID, so the script can read
      # them without us having to loosen the on-disk perms in
      # /etc/nixos/secrets.
      systemd.services.ntfy-sh = {
        # Poll_request POSTs to ntfy.sh. At boot ntfy was coming up
        # before Unbound, so the first publishes logged
        # "lookup ntfy.sh: no such host" and iOS never got a wakeup.
        after = [
          "network-online.target"
          "nss-lookup.target"
        ];
        wants = [ "network-online.target" ];
        serviceConfig = lib.mkIf needsProvisioning {
          ExecStartPre = [ "${provisionUsers}/bin/ntfy-sh-provision-users" ];
          LoadCredential = adminCredArg ++ extraCredArgs;
        };
      };

      # Scrape the dedicated metrics port when Prometheus is enabled on
      # the same host. Job name is "ntfy" so prometheus-rules.nix can
      # match it. Inherit custom.prometheus.scrapeInterval when that
      # module is in play (5s in the observability VM test, 15s default).
      services.prometheus.scrapeConfigs = lib.mkIf config.services.prometheus.enable [
        {
          job_name = "ntfy";
          scrape_interval =
            if (config.custom ? prometheus && config.custom.prometheus.enable) then
              config.custom.prometheus.scrapeInterval
            else
              "15s";
          static_configs = [
            {
              targets = [ "127.0.0.1:${toString cfg.metricsPort}" ];
            }
          ];
        }
      ];
    }
  );
}

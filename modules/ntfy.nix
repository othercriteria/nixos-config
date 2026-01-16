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

{ config, lib, pkgs, ... }:

let
  cfg = config.custom.ntfy;
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
        Upstream ntfy server for UnifiedPush. Mobile apps can use this
        to receive notifications even when your server is unreachable.
      '';
    };

    auth = {
      enable = lib.mkEnableOption "authentication for ntfy";

      defaultAccess = lib.mkOption {
        type = lib.types.enum [ "read-write" "read-only" "write-only" "deny-all" ];
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
  };

  config = lib.mkIf cfg.enable {
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

        # UnifiedPush support - allows apps to use your server as a UP distributor
        # Falls back to upstream for delivery when your server is unreachable
        upstream-base-url = cfg.upstreamBaseUrl;

        # Logging
        log-level = "info";
      } // lib.optionalAttrs cfg.auth.enable {
        # Authentication
        auth-file = "/var/lib/ntfy-sh/user.db";
        auth-default-access = cfg.auth.defaultAccess;
      };
    };

    # Ensure state directories exist
    systemd.services.ntfy-sh.serviceConfig = {
      StateDirectory = "ntfy-sh";
    };

    # Setup script to create/update admin user when auth is enabled
    # Runs before ntfy starts to ensure user exists
    systemd.services.ntfy-sh-setup = lib.mkIf (cfg.auth.enable && cfg.auth.passwordFile != null) {
      description = "Setup ntfy-sh admin user";
      wantedBy = [ "ntfy-sh.service" ];
      before = [ "ntfy-sh.service" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        StateDirectory = "ntfy-sh";
      };
      script = ''
        AUTH_FILE="/var/lib/ntfy-sh/user.db"
        export NTFY_AUTH_FILE="$AUTH_FILE"
        export NTFY_PASSWORD=$(cat "${cfg.auth.passwordFile}")

        # Create or update the admin user
        if ! ${pkgs.ntfy-sh}/bin/ntfy user list 2>/dev/null | grep -q "^user ${cfg.auth.username}"; then
          echo "Creating ntfy admin user '${cfg.auth.username}'..."
          ${pkgs.ntfy-sh}/bin/ntfy user add --role=admin ${cfg.auth.username}
        else
          echo "Updating admin user password..."
          ${pkgs.ntfy-sh}/bin/ntfy user change-pass ${cfg.auth.username} || true
        fi

        echo "ntfy user setup complete"
      '';
    };
  };
}

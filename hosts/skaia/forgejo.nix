{ config, lib, pkgs, ... }:

let
  forgejoHost = "forgejo.home.arpa";
  forgejoPort = 3044;
in
{
  environment.systemPackages = with pkgs; [
    forgejo
  ];

  services = {
    # Keep PostgreSQL local for the MVP. Using the default unix socket path lets
    # the built-in Forgejo module create and own the database declaratively.
    #
    # Future refinement: move PostgreSQL, Forgejo app state, repositories, and
    # LFS onto dedicated ZFS datasets once those datasets have been created. The
    # first deploy intentionally avoids hard mount dependencies so a missing
    # dataset cannot wedge boot again.
    postgresql = {
      enable = true;
    };

    forgejo = {
      enable = true;

      # Start private-first on the LAN. Once the service has settled, the
      # obvious next step is to front the web UI with Teleport application
      # access, and only then consider a public DNS/TLS endpoint if it still
      # feels worth the extra attack surface.
      stateDir = "/var/lib/forgejo";
      repositoryRoot = "/var/lib/forgejo-repositories";

      database = {
        type = "postgres";
      };

      lfs = {
        enable = true;
        contentDir = "/var/lib/forgejo-lfs";
      };

      dump = {
        enable = true;
        backupDir = "/bulk/forgejo-backups";
      };

      settings = {
        server = {
          DOMAIN = forgejoHost;
          ROOT_URL = "http://${forgejoHost}/";
          HTTP_ADDR = "127.0.0.1";
          HTTP_PORT = forgejoPort;

          # Prefer a smaller initial surface area. HTTPS remotes work fine for
          # single-user operation, and SSH can be added later once the service is
          # stable and the desired access path is clearer.
          DISABLE_SSH = true;
        };

        service = {
          DISABLE_REGISTRATION = true;
          REQUIRE_SIGNIN_VIEW = true;
        };

        session = {
          # The MVP is LAN-only over plain HTTP. Switch this to true when the UI
          # moves behind HTTPS or Teleport app access.
          COOKIE_SECURE = false;
        };

        repository = {
          ENABLE_PUSH_CREATE_USER = true;
        };
      };
    };
  };

  systemd.tmpfiles.rules = [
    # COLD START: Create the backup parent if /bulk is present but the Forgejo
    # subdirectory does not yet exist. Later revisions may want a dedicated ZFS
    # dataset or replicated snapshot workflow for this path.
    "d /bulk/forgejo-backups 0750 forgejo forgejo -"
  ];

  # COLD START: Bootstrap the first admin user after the service is up:
  #
  #   sudo -u forgejo forgejo admin user create \
  #     --config /var/lib/forgejo/custom/conf/app.ini \
  #     --username dlk \
  #     --email othercriteria@gmail.com \
  #     --admin \
  #     --password 'choose-a-strong-password'
  #
  # Once that succeeds, log in at http://forgejo.home.arpa/ and generate a PAT
  # for local CLI/agent access. If we later want this to be fully declarative,
  # the next refinement is a secret-backed preStart hook that ensures the admin
  # account exists without storing the password in the nix store.
}

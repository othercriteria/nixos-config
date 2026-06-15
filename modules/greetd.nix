{ pkgs, ... }:
{
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        # NOTE: keep this on a single line. A multi-line Nix string makes
        # pkgs.formats.toml emit a TOML '''…''' literal block, which
        # greetd 0.10.3's parser rejects ("expected equals sign on line,
        # but found none") and the service fails to start.
        command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --user-menu --cmd '${pkgs.uwsm}/bin/uwsm start /etc/profiles/per-user/dlk/bin/sway'";
      };
    };
  };

  # Increase file descriptor limit for greetd to prevent exhaustion
  # Default systemd limit (1024) is insufficient for sessions with many apps
  systemd.services.greetd.serviceConfig.LimitNOFILE = 65536;
}

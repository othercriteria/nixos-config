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
        #
        # Default session is the desktop entry from
        # programs.uwsm.waylandCompositors.sway (sway-uwsm.desktop →
        # `uwsm start -F -- <hm-sway>`). -g -1 disables UWSM's default 60s
        # wait for system graphical.target: with greetd that target often
        # only becomes active after auth, so the wait added ~45s of black
        # screen before sway. -g is applied before desktop-entry reparsing.
        # --sessions exposes "Sway (UWSM)" in tuigreet if overridden.
        command = "${pkgs.tuigreet}/bin/tuigreet --time --asterisks --user-menu --sessions /run/current-system/sw/share/wayland-sessions --cmd '${pkgs.uwsm}/bin/uwsm start -g -1 sway-uwsm.desktop'";
      };
    };
  };

  # Increase file descriptor limit for greetd to prevent exhaustion
  # Default systemd limit (1024) is insufficient for sessions with many apps
  systemd.services.greetd.serviceConfig.LimitNOFILE = 65536;
}

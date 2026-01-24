{ pkgs, ... }:
{
  services.greetd = {
    enable = true;
    useTextGreeter = true;
    settings = {
      default_session = {
        command = ''
          ${pkgs.tuigreet}/bin/tuigreet \
            --time \
            --asterisks \
            --user-menu \
            --cmd '${pkgs.uwsm}/bin/uwsm start /etc/profiles/per-user/dlk/bin/sway'
        '';
      };
    };
  };

  # Increase file descriptor limit for greetd to prevent exhaustion
  # Default systemd limit (1024) is insufficient for sessions with many apps
  systemd.services.greetd.serviceConfig.LimitNOFILE = 65536;
}

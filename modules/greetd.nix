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
}

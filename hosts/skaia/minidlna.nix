{ config, ... }:

{
  services.minidlna = {
    enable = true;
    settings = {
      notify_interval = 60;
      inotify = "yes";
      friendly_name = "skaia";
      media_dir = [ "V,/bulk/dlk" ];
    };
  };

  users.users.minidlna.extraGroups = [ "users" ];
}

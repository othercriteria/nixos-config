{ config, ... }:

{
  services.minidlna = {
    enable = true;
    settings = {
      notify_interval = 60;
      inotify = "yes";
      friendly_name = "skaia";
      # Library root only. inotify watches every directory, and
      # pointing this at /bulk/dlk exhausts the host watch budget.
      media_dir = [ "V,/bulk/dlk/media" ];
    };
  };

  users.users.minidlna.extraGroups = [ "users" ];
}

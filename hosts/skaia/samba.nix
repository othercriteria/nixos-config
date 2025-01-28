{ config, ... }:

{
  services.samba = {
    enable = true;
    settings = {
      global = {
        security = "user";
        workgroup = "WORKGROUP";
        "server string" = "skaia";
        "server role" = "standalone server";
        "netbios name" = "skaia";
        "hosts allow" = "192.168.0.0/24, localhost";
        "hosts deny" = "0.0.0.0/0";
        "log file" = "/var/log/samba/smbd.%m";
        "max log size" = "1000";
      };
      "dlk" = {
        path = "/bulk/dlk/share-samba";
        "browseable" = "yes";
        "read only" = "no";
        "guest ok" = "no";
        "create mask" = "0664";
        "directory mask" = "0775";
        "force user" = "share";
      };
    };
  };

  users.groups.share = { };

  users.extraUsers = {
    share = {
      # This requires `smbpasswd -a share` to work...
      group = "share";
      isSystemUser = true;
    };
  };
}

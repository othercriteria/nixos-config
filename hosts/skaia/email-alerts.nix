{ config, pkgs, ... }:

let
  inherit (config.networking) hostName;
  emailTo = "daniel.l.klein@pm.me";
  emailFrom = "daniel.l.klein@pm.me";

  sendEmailEvent = { event }: ''
    printf "Subject: ${hostName} ${event} $(${pkgs.coreutils}/bin/date --iso-8601=seconds)\n\nzpool status:\n\n$(${pkgs.zfs}/bin/zpool status)" | ${pkgs.msmtp}/bin/msmtp -a default ${emailTo}
  '';
in
{
  nixpkgs.config.packageOverrides = pkgs: {
    zfsStable = pkgs.zfsStable.override { enableMail = true; };
  };

  programs.msmtp = {
    enable = true;
    accounts.default = {
      auth = "plain";
      host = "127.0.0.1";
      port = 1025;
      from = emailFrom;
      user = emailFrom;
      passwordeval = "cat /etc/nixos/secrets/dlk-protonmail-password";
      tls = false;
      tls_starttls = false;
    };
  };

  systemd.services = {
    hydroxide = {
      description = "Hydroxide";
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        # TODO: fix the hack of having to use an ordinary user here
        # With the default user, it fails like:
        # 454 4.7.0 failed to get auth file path: neither $XDG_CONFIG_HOME nor $HOME are defined
        User = "dlk";
        ExecStart = "${pkgs.hydroxide}/bin/hydroxide smtp";
        Restart = "always";
        RestartSec = "5";
      };
    };
    "boot-mail-alert" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "hydroxide.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "hydroxide.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = sendEmailEvent { event = "just booted"; };
    };
    "shutdown-mail-alert" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "hydroxide.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "hydroxide.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "true";
      preStop = sendEmailEvent { event = "is shutting down"; };
    };
    "weekly-mail-alert" = {
      serviceConfig.Type = "oneshot";
      after = [ "hydroxide.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "hydroxide.service" ];
      script = sendEmailEvent { event = "is still alive"; };
    };
  };

  systemd.timers."weekly-mail-alert" = {
    wantedBy = [ "timers.target" ];
    partOf = [ "weekly-mail-alert.service" ];
    after = [ "hydroxide.service" ];
    requires = [ "hydroxide.service" ];
    timerConfig.OnCalendar = "weekly";
  };
}

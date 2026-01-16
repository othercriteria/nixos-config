{ config, pkgs, ... }:

let
  inherit (config.networking) hostName;
  emailTo = "daniel.l.klein@pm.me";
  emailFrom = "daniel.l.klein@pm.me";

  # ntfy notification helper - instant push notifications
  # Uses basic auth from secrets file
  sendNtfyEvent = { event, priority ? "default", tags ? "computer" }: ''
        NTFY_PASS=$(cat /etc/nixos/secrets/ntfy-password)
        ${pkgs.curl}/bin/curl -s \
          -u "dlk:$NTFY_PASS" \
          -H "Title: ${hostName} ${event}" \
          -H "Priority: ${priority}" \
          -H "Tags: ${tags}" \
          -d "$(${pkgs.coreutils}/bin/date --iso-8601=seconds)

    zpool status:
    $(${pkgs.zfs}/bin/zpool status)" \
          http://127.0.0.1:8090/system-events || true
  '';

  # Email notification helper - audit trail
  sendEmailEvent = { event }: ''
    printf "Subject: ${hostName} ${event} $(${pkgs.coreutils}/bin/date --iso-8601=seconds)\n\nzpool status:\n\n$(${pkgs.zfs}/bin/zpool status)" | ${pkgs.msmtp}/bin/msmtp -a default ${emailTo}
  '';

  # Combined notification - ntfy for instant alert, email for records
  sendBothEvents = { event, priority ? "default", tags ? "computer" }: ''
    ${sendNtfyEvent { inherit event priority tags; }}
    ${sendEmailEvent { inherit event; }}
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
      after = [ "hydroxide.service" "ntfy-sh.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "hydroxide.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = sendBothEvents { event = "just booted"; tags = "white_check_mark,computer"; };
    };
    "shutdown-mail-alert" = {
      wantedBy = [ "multi-user.target" ];
      after = [ "hydroxide.service" "ntfy-sh.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "hydroxide.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "true";
      preStop = sendBothEvents { event = "is shutting down"; priority = "high"; tags = "warning,computer"; };
    };
    "weekly-mail-alert" = {
      serviceConfig.Type = "oneshot";
      after = [ "hydroxide.service" "ntfy-sh.service" "network-online.target" ];
      wants = [ "network-online.target" ];
      requires = [ "hydroxide.service" ];
      script = sendBothEvents { event = "is still alive"; tags = "heartbeat"; };
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

{ pkgs, ... }:

{
  i18n.inputMethod = {
    enable = true;
    type = "fcitx5";
    fcitx5 = {
      addons = with pkgs; [
        qt6Packages.fcitx5-chinese-addons
        fcitx5-mozc
        fcitx5-gtk
        libsForQt5.fcitx5-qt
        qt6Packages.fcitx5-qt
      ];
      waylandFrontend = true;
      # sway.nix starts `fcitx5 -rd`. The user unit waits on
      # graphical-session.target, which UWSM does not activate.
      systemd.enable = false;
      settings = {
        globalOptions = {
          Behavior = {
            ActiveByDefault = false;
            AllowInputMethodForPassword = false;
            CompactInputMethodInformation = true;
            DefaultPageSize = 5;
            PreloadInputMethod = true;
            ShowFirstInputMethodInformation = true;
            ShowInputMethodInformation = true;
          };
          Hotkey = {
            EnumerateSkipFirst = false;
            EnumerateWithTriggerKeys = true;
            ModifierOnlyKeyTimeout = 250;
          };
          "Hotkey/AltTriggerKeys"."0" = "Shift_L";
          "Hotkey/EnumerateGroupBackwardKeys"."0" = "Alt+question";
          "Hotkey/EnumerateGroupForwardKeys"."0" = "Alt+slash";
          "Hotkey/NextCandidate"."0" = "Tab";
          "Hotkey/NextPage"."0" = "Down";
          "Hotkey/PrevCandidate"."0" = "Shift+Tab";
          "Hotkey/PrevPage"."0" = "Up";
          "Hotkey/TriggerKeys"."0" = "Alt+space";
        };
        inputMethod = {
          GroupOrder."0" = "Default";
          "Groups/0" = {
            Name = "Default";
            "Default Layout" = "us";
            DefaultIM = "pinyin";
          };
          "Groups/0/Items/0" = {
            Name = "keyboard-us";
            Layout = "";
          };
          "Groups/0/Items/1" = {
            Name = "pinyin";
            Layout = "us";
          };
        };
      };
    };
  };

  # fcitx saves profile as a regular file, which the new Home Manager
  # refuses to replace. Link the managed leaves into the existing
  # directory so conf/ stays writable, and replace those leaves on
  # every activation.
  xdg.configFile.fcitx5 = {
    recursive = true;
    force = true;
  };
}

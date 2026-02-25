{ pkgs, lib, ... }:

let
  berkeleyMonoZip = ../private-assets/fonts/berkeley-mono/berkeley-mono-typeface-2.002.zip;
  berkeleyMonoPkg = if builtins.pathExists berkeleyMonoZip then [ (pkgs.callPackage ./berkeley-mono-typeface.nix { }) ] else [ ];
in
{
  fonts = {
    fontDir.enable = true;
    fontconfig = {
      enable = true;
      antialias = true;

      defaultFonts = {
        serif = [ "Cambria" ];
        sansSerif = [ "Ubuntu" ];
        monospace = [ "Berkeley Mono" ];
        emoji = [ "Noto Color Emoji" ];
      };
    };

    enableGhostscriptFonts = true;
    packages = with pkgs;
      [
        anonymousPro
        cantarell-fonts
        dejavu_fonts
        hack-font
        hanazono
        inconsolata
        inter
        ipafont
        liberation_ttf
        meslo-lg
        monaspace
        noto-fonts
        noto-fonts-color-emoji
        noto-fonts-cjk-sans
        font-awesome
        powerline-fonts
        source-code-pro
        source-han-sans
        source-han-serif
        ubuntu-classic
        unifont
        vista-fonts
        nerd-fonts.droid-sans-mono
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
      ] ++ berkeleyMonoPkg; # COLD START: Optional private font asset if present
  };
}

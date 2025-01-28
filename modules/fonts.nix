{ pkgs, ... }:

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
      };
    };

    enableGhostscriptFonts = true;
    packages = with pkgs;
      [
        anonymousPro
        (pkgs.callPackage ./berkeley-mono-typeface.nix { })
        cantarell-fonts
        dejavu_fonts
        hack-font
        hanazono
        inconsolata
        inter
        ipafont
        jetbrains-mono
        liberation_ttf
        meslo-lg
        monaspace
        noto-fonts
        noto-fonts-cjk-sans
        powerline-fonts
        source-code-pro
        source-han-sans
        source-han-serif
        ubuntu_font_family
        unifont
        vistafonts
        nerd-fonts.droid-sans-mono
        nerd-fonts.fira-code
        nerd-fonts.jetbrains-mono
      ];
  };
}

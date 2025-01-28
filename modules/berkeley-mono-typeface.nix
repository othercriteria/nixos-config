{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "berkeley-mono-typeface";
  version = "1.009";

  buildInputs = [ pkgs.unzip ];

  src = ../assets/berkeley-mono-typeface.zip;

  unpackPhase = ''
    runHook preUnpack

    unzip $src

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 berkeley-mono/TTF/*.ttf -t $out/share/fonts/truetype

    runHook postInstall
  '';
}

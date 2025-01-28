{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "berkeley-mono-typeface";
  version = "1.009";

  buildInputs = [ pkgs.unzip ];

  src = ../private-assets/fonts/berkeley-mono/berkeley-mono-typeface-2.002.zip;

  unpackPhase = ''
    runHook preUnpack

    unzip $src

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 **/*.ttf -t $out/share/fonts/truetype

    runHook postInstall
  '';
}

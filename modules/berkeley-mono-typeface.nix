{ pkgs, ... }:

pkgs.stdenv.mkDerivation {
  pname = "berkeley-mono-typeface";
  version = "2.002";

  buildInputs = [ pkgs.unzip ];

  src = ../private-assets/fonts/berkeley-mono/berkeley-mono-typeface-2.002.zip;

  unpackPhase = ''
    runHook preUnpack

    unzip $src

    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 250128P42JQ77JNP/TX-02-7WQPNNQY/*.ttf -t $out/share/fonts/truetype

    runHook postInstall
  '';
}

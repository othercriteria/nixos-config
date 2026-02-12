# Interactive Brokers Trader Workstation
#
# Uses buildFHSEnv to run the official installer in a proper Linux environment.
# This approach is more robust than byte-offset extraction as it handles
# installer format changes automatically.
{ pkgs }:

let
  # FHS environment for running the installer
  fhsEnv = pkgs.buildFHSEnv {
    name = "tws-installer-env";
    targetPkgs = pkgs: with pkgs; [
      # Basic requirements
      bash
      coreutils
      gawk
      gnugrep
      gnused
      gnutar
      gzip
      which

      # X11/GUI requirements
      libx11
      libxext
      libxrender
      libxtst
      libxi
      gtk2
      gtk3
      glib
      pango
      cairo
      gdk-pixbuf
      atk

      # Java/system requirements
      zlib
      libGL
      alsa-lib
      freetype
      fontconfig
    ];
    runScript = "bash";
  };

  # Runtime library path for TWS
  libPath = pkgs.lib.makeLibraryPath (with pkgs; [
    alsa-lib
    at-spi2-atk
    cairo
    cups
    dbus
    expat
    ffmpeg
    fontconfig
    freetype
    gdk-pixbuf
    glib
    gtk2
    gtk3
    libdrm
    libGL
    libxkbcommon
    mesa
    nspr
    nss
    pango
    libx11
    libxcomposite
    libxdamage
    libxext
    libxfixes
    libxi
    libxrandr
    libxrender
    libxtst
    libxxf86vm
    libxcb
    zlib
  ]);

  installer = pkgs.fetchurl {
    url = "https://download2.interactivebrokers.com/installers/tws/latest-standalone/tws-latest-standalone-linux-x64.sh";
    hash = "sha256-GDW5KPxT/wZTcyZQ0BzcztQNxPE8uLgPa/gfi6Csb5U="; # pragma: allowlist secret
  };

in
pkgs.stdenv.mkDerivation {
  pname = "ib-tws";
  version = "latest";

  src = installer;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;

  # Run installer in FHS environment
  installPhase = ''
    runHook preInstall

    mkdir -p $out

    # Copy installer to writable location
    cp ${installer} ./installer.sh
    chmod +x ./installer.sh

    # Run the installer in FHS environment
    # Use -Dinstall4j.keepModuleDir=true to prevent cleanup of extracted files
    ${fhsEnv}/bin/tws-installer-env -c "
      export INSTALL4J_KEEP_TEMP=true
      ./installer.sh -q -dir $out -Dinstall4j.keepModuleDir=true

      # Find the extracted JRE - it's in .local/share/i4j_jres/
      JRE_SRC=\$(find .local/share/i4j_jres -maxdepth 2 -type d -name '*zulu*' 2>/dev/null | head -1)

      if [ -n \"\$JRE_SRC\" ] && [ -d \"\$JRE_SRC/bin\" ]; then
        echo \"Found JRE at: \$JRE_SRC\"
        cp -r \"\$JRE_SRC\" $out/jre
      else
        echo \"ERROR: Could not find JRE\"
        find . -name 'java' -type f 2>/dev/null | head -5 || true
      fi
    "

    # Patch the JRE binaries for NixOS
    if [ -d "$out/jre/bin" ]; then
      echo "Patching JRE binaries and libraries..."

      # Patch executables
      for file in $out/jre/bin/*; do
        if [ -f "$file" ] && [ -x "$file" ]; then
          patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$file" 2>/dev/null || true
          patchelf --set-rpath "${libPath}:$out/jre/lib" "$file" 2>/dev/null || true
        fi
      done

      # Patch shared libraries
      find $out/jre -name "*.so*" -type f | while read -r lib; do
        patchelf --set-rpath "${libPath}:$out/jre/lib" "$lib" 2>/dev/null || true
      done

      # Update the JRE config
      echo "$out/jre" > $out/.install4j/pref_jre.cfg
    else
      echo "ERROR: JRE not found after install!"
      echo "Listing temp directories..."
      find /tmp -type d -name "*.dir" 2>/dev/null | head -10 || true
      exit 1
    fi

    # Create wrapper script
    mkdir -p $out/bin
    makeWrapper $out/tws $out/bin/tws \
      --prefix LD_LIBRARY_PATH : "${libPath}" \
      --set INSTALL4J_JAVA_HOME "$out/jre" \
      --add-flags "-J-DjtsConfigDir=\$HOME/.tws" \
      --add-flags "-J-Djdk.gtk.version=2"

    runHook postInstall
  '';

  meta = with pkgs.lib; {
    description = "Interactive Brokers Trader Workstation";
    homepage = "https://www.interactivebrokers.com";
    license = licenses.unfree;
    platforms = [ "x86_64-linux" ];
    mainProgram = "tws";
  };
}

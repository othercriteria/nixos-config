{
  description = "Static site for the-baltic-approaches, built to the repo's deployment contract";

  # Deliberately one input. The book repo owns its build environment; this
  # flake takes both the toolchain and nixpkgs from it rather than pinning
  # anything of its own, so a change to the book's devShell is picked up
  # here with no edit on the serving side. See planning/site-handoff.md in
  # the book repo for the contract this implements.
  inputs.baltic.url = "github:othercriteria/the-baltic-approaches";

  outputs =
    { self, baltic }:
    let
      system = "x86_64-linux";
      pkgs = baltic.inputs.nixpkgs.legacyPackages.${system};
      shell = baltic.devShells.${system}.default;
    in
    {
      packages.${system} = {
        default = self.packages.${system}.site;

        site = pkgs.stdenvNoCC.mkDerivation {
          pname = "the-baltic-approaches-site";
          version = baltic.shortRev or "dirty";
          src = baltic;

          # `nix develop` is the contract's supported build environment, so
          # take its package set verbatim. FONTCONFIG_FILE is set on the
          # devShell to pin the TeX Gyre faces the cover is set in; without
          # it xelatex falls back to host fonts, which a build sandbox and a
          # headless server do not have.
          inherit (shell) nativeBuildInputs FONTCONFIG_FILE;

          buildPhase = ''
            runHook preBuild

            # xelatex and fontconfig both want somewhere to write caches.
            export HOME="$TMPDIR/home"
            export TEXMFVAR="$TMPDIR/texmf-var"
            mkdir -p "$HOME" "$TEXMFVAR"

            # The deploy gate. A failing suite fails the build, which leaves
            # the previous result in place rather than publishing it.
            make test
            make site

            runHook postBuild
          '';

          installPhase = ''
            runHook preInstall
            cp -r build/site "$out"
            runHook postInstall
          '';

          # Cheap guard against a silently truncated assembly: serving a page
          # with a missing or empty part is worse than failing the deploy.
          #
          # The named list is transcribed from the contract's file table and
          # so can lag the book: the /making/ split shipped before the table
          # listed it, and this check inherited that omission. The empty-file
          # sweep below is the drift-proof half -- it covers whatever the
          # build emits, including pages added since this list was written.
          doInstallCheck = true;
          installCheckPhase = ''
            for f in index.html site.css site.js cover.jpg llms.txt making/index.html; do
              if [ ! -s "$out/$f" ]; then
                echo "site build is missing or empty: $f" >&2
                exit 1
              fi
            done

            if find "$out" -type f -empty -print | grep -q .; then
              echo "site build emitted empty files:" >&2
              find "$out" -type f -empty -printf '  %P\n' >&2
              exit 1
            fi
          '';

          meta = {
            description = "valueof.info/the-baltic-approaches/ static page";
            platforms = [ system ];
          };
        };
      };
    };
}

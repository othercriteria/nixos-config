{
  description = "Static résumé site for valueof.info/daniel-klein-resume/, built to the résumé repo's deployment contract";

  # Deliberately one input, as in modules/baltic-site/site-flake: the résumé
  # repo owns its toolchain (pandoc, xelatex, the declared fonts) and this
  # flake takes nixpkgs from it rather than pinning anything of its own.
  inputs.resume.url = "github:othercriteria/resume";

  outputs =
    { self, resume }:
    let
      system = "x86_64-linux";
    in
    {
      packages.${system} = {
        default = self.packages.${system}.site;
        # The résumé flake's own package already runs `make test` (the
        # deploy gate) then `make site`, in the devShell's environment with
        # FONTCONFIG_FILE pinned, and install-checks for missing or empty
        # output. Re-export it so the deploy script's `#site` reference
        # matches the book page's.
        site = resume.packages.${system}.site;
      };
    };
}

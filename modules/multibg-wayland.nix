{ lib, rustPlatform, fetchFromGitHub }:

rustPlatform.buildRustPackage rec {
  pname = "multibg-wayland";
  version = "0.2.4";

  src = fetchFromGitHub {
    owner = "gergo-salyi";
    repo = "multibg-wayland";
    rev = version; # No 'v' prefix on tags
    hash = "sha256-gQcYvP5dpMxv5W4Po3G265hQUoqQJssb0aZwDktoqXk="; # pragma: allowlist secret
  };

  cargoHash = "sha256-szhWFYhO11ZTdWQ/G1q4rUlgl9TLTQ/T5VL4UbDJBQY="; # pragma: allowlist secret

  meta = with lib; {
    description = "Set a different wallpaper for the background of each Sway workspace";
    homepage = "https://github.com/gergo-salyi/multibg-wayland";
    license = with licenses; [ asl20 mit ];
    platforms = platforms.linux;
  };
}

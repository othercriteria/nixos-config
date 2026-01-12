{ pkgs, ... }:

{
  # COLD START: Printers are configured imperatively via CUPS. After installing
  # NixOS, add the printer via http://localhost:631/admin or lpadmin CLI.
  # See docs/COLD-START.md section 25 for detailed steps.
  #
  # Important: Printer URIs must use .local suffix for mDNS resolution
  # (e.g., lpd://BRWD89C672FCCC5.local/BINARY_P1). Avahi/mDNS must be enabled
  # on the host (provided by airplay.nix on skaia).

  services = {
    # Reduce attack surface by disabling CUPS browsing
    printing.browsed.enable = false;

    # Avahi disabled by default here; hosts that need mDNS (e.g., for AirPlay
    # or printer discovery) should enable it explicitly with mkForce.
    avahi.enable = false;

    printing = {
      enable = true;
      drivers = [ pkgs.brlaser ];
    };
  };

  # TODO: Printers are interactively configured via `http://localhost:631/`, but
  # perhaps we can do this declaratively...
}

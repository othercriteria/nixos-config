{ pkgs, ... }:

{
  services = {
    # Reduce attack surface by disabling CUPS browsing
    printing.browsed.enable = false;

    # Reduce attack surfaces by zeroconf services
    avahi.enable = false;

    printing = {
      enable = true;
      drivers = [ pkgs.brlaser ];
    };
  };

  # TODO: Printers are interactively configured via `http://localhost:631/`, but
  # perhaps we can do this declaratively...
}

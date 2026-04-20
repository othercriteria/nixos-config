{ pkgs, ... }:

{
  virtualisation = {
    # podman = {
    #   enable = true;
    #
    #   dockerCompat = true;
    #   defaultNetwork.settings.dns_enabled = true;
    # };

    docker = {
      enable = true;
      daemon.settings = {
        default-ulimits = {
          nofile = {
            name = "nofile";
            hard = 64000;
            soft = 64000;
          };
        };
      };
    };

    containerd.enable = true;

    virtualbox.host = {
      enable = true;
      enableExtensionPack = true;
    };
  };

  # Periodic Docker cleanup beyond what `virtualisation.docker.autoPrune`
  # offers (which only runs `docker system prune -f` and won't touch tagged
  # images or build cache).
  #
  # Context: the `skaia-rpm` GitHub Actions runner builds
  # `localhost:5000/decapod:git-<sha>` images and pushes them to the local
  # registry. Nothing on the Docker daemon itself consumes those images (k3s
  # pulls from localhost:5000 via its own containerd), but each build leaves
  # the tagged image plus build-cache layers behind. Left unpruned, this
  # caused dockerd + the system containerd to burn ~3-4 CPU cores each
  # continuously, because periodic `/images/json` polls (e.g. from netdata's
  # docker collector) fan out into per-image `snapshotter.Usage` /
  # `snapshotter.Stat` calls that are slow enough to time out and retry.
  #
  # Mirrors the `k3s-ephemeral-prune` pattern in hosts/skaia/k3s/default.nix.
  # Named `docker-deep-prune` to avoid colliding with the upstream
  # `docker-prune.service` declared by the docker module.
  systemd.services.docker-deep-prune = {
    description = "Deep prune of Docker tagged images and build cache";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    serviceConfig = {
      Type = "oneshot";
    };
    path = [ pkgs.docker pkgs.coreutils pkgs.gawk pkgs.findutils ];
    script = ''
      set -euo pipefail

      # Remove every localhost:5000/decapod:* tag. These are CI build
      # artifacts that the Docker daemon never consumes -- k3s pulls them
      # from the registry directly. If a human needs one back, it's still in
      # the registry.
      tags=$(docker images --format '{{.Repository}}:{{.Tag}}' \
        | awk '/^localhost:5000\/decapod:/' || true)
      if [ -n "$tags" ]; then
        echo "Removing $(echo "$tags" | wc -l) decapod image tags..."
        echo "$tags" | xargs -r docker rmi -f || true
      fi

      # Drop any other images unreferenced and older than 7 days. docker
      # refuses to remove images still in use by containers, so this is safe.
      echo "Pruning images unused for >168h..."
      docker image prune -af --filter "until=168h" || true

      # Build cache is unreferenced by definition once a build completes.
      echo "Pruning build cache..."
      docker builder prune -af || true
    '';
  };

  systemd.timers.docker-deep-prune = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
      RandomizedDelaySec = "30m";
    };
  };
}

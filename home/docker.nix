{ lib, ... }:

{
  # Registers a persistent `registry-cache` buildx builder in dlk's
  # ~/.docker/buildx/ so `poe docker-build` (in rearguard-portfolio-management)
  # and similar tasks can use a registry-backed BuildKit cache via:
  #
  #   docker buildx build --builder registry-cache \
  #     --cache-from type=registry,ref=localhost:5000/<project>:buildcache \
  #     --cache-to   type=registry,ref=localhost:5000/<project>:buildcache,mode=max \
  #     --push ...
  #
  # Rationale: the docker-container driver runs a long-lived moby/buildkit
  # container whose state survives across builds, and `--push` outputs
  # directly to the registry so the host Docker daemon never accumulates
  # tagged intermediate images (the root cause of the docker-deep-prune
  # work in hosts/skaia/virtualisation.nix).
  #
  # network=host lets the buildkit container reach localhost:5000 (the
  # host-local docker-registry service) without any address juggling on the
  # caller side; everyone keeps saying `localhost:5000` as before.
  #
  # NOTE: if/when a registry-cleanup tool is turned into something
  # repo-managed, make sure it preserves tags matching `*:buildcache`;
  # the durable BuildKit cache lives there and is not pinned by any
  # running workload, so a naive "delete everything not referenced by
  # kubectl" sweep would silently nuke it and force a full rebuild.
  home.activation.registerRegistryCacheBuildx =
    lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      PATH="/run/current-system/sw/bin:$PATH"

      if ! command -v docker >/dev/null 2>&1; then
        $VERBOSE_ECHO "docker CLI not on PATH; skipping registry-cache buildx setup"
      elif ! docker info >/dev/null 2>&1; then
        # Daemon not up yet (e.g. first activation after reboot before
        # docker.service settles). Leave this as a no-op; the next
        # home-manager activation will pick it up.
        $VERBOSE_ECHO "Docker daemon not reachable; skipping registry-cache buildx setup"
      elif docker buildx inspect registry-cache >/dev/null 2>&1; then
        $VERBOSE_ECHO "registry-cache buildx builder already registered"
      else
        echo "Creating registry-cache buildx builder (docker-container, network=host)..."
        docker buildx create \
          --name registry-cache \
          --driver docker-container \
          --driver-opt network=host \
          >/dev/null
      fi
    '';
}

# Netdata 2.11.0 added a CMake `go run ./cmd/snmptrapprofilegen` step
# (and a similar eBPF Go plugin command) with hardcoded
# GOPROXY=https://proxy.golang.org,direct. nixpkgs only rewrites GOPROXY
# in NetdataGoTools.cmake, so those extra `go run`/`go build` commands
# try DNS in the sandbox and fail.
#
# Drop this overlay once nixpkgs rewrites GOPROXY in CMakeLists.txt
# (and vendors `src/go` rather than the old `src/go/plugin/go.d`
# module root).
pkg:
pkg.overrideAttrs (old: {
  preConfigure = old.preConfigure + ''
    substituteInPlace CMakeLists.txt \
      --replace-fail \
        'GOPROXY=https://proxy.golang.org,direct' \
        'GOPROXY=file://${old.passthru.netdata-go-modules},file://${old.passthru.nd-mcp}'
  '';
})

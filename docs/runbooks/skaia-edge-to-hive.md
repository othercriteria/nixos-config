# Skaia → Hive Edge Relocation

Move the public-facing reverse-proxy / dynamic-DNS / ACME surface
from `skaia` to `hive` so that `skaia` can run ProtonVPN as the
default network configuration without breaking inbound public
traffic. Backends (the actual services behind the vhosts) mostly
stay where they are; only the **edge** moves.

This is the structural fix for the asymmetric-routing footgun
documented in [modules/protonvpn.nix][protonvpn-caveat] (May 2026:
ddclient briefly published a Meta-owned ProtonVPN exit IP because
the default route was pointing into the tunnel while the GUI VPN
was active).

[protonvpn-caveat]: ../../modules/protonvpn.nix

## Goal

After this runbook, `hive` owns:

- The TP-Link router's TCP `80` / `443` (and TCP `3023` / `3024`
  if Teleport also moves; see § "Teleport carve-out") port
  forwards.
- The nginx reverse proxy for all `*.valueof.info` vhosts.
- The `security.acme` ACME state for those certificates.
- The `ddclient` instance that publishes the home WAN IP to
  Namecheap dynamic DNS.

`skaia` retains:

- LAN-only vhosts (`forgejo.home.arpa`, `netdata.home.arpa`,
  `cache.home.arpa`, `ollama.home.arpa`, `assistant.home.arpa`).
- The actual backend services for ntfy, trivia, Home Assistant,
  SRS streaming, Harmonia, Forgejo, etc., bound to a LAN IP so
  hive's nginx can reach them.
- Teleport unless the carve-out below is taken.

`skaia` can then run with ProtonVPN as the default route because
no public WAN traffic needs to terminate on it (modulo Teleport).

## Inventory (as of 2026-05-26)

Public vhosts that need to move off `skaia`:

| Vhost                       | Backend (today)                       | Backend rebind needed                | Notes                                                  |
|-----------------------------|---------------------------------------|--------------------------------------|--------------------------------------------------------|
| `valueof.info`              | static page (in-tree)                 | n/a (move file)                      | trivial                                                |
| `teleport.valueof.info`     | `127.0.0.1:3080` on skaia (Teleport)  | bind to LAN IP or move Teleport      | see § "Teleport carve-out"                             |
| `urbit.valueof.info`        | `hive.home.arpa:8080`                 | none — already on hive               | easiest of the bunch                                   |
| `stiletto.valueof.info`     | `192.168.0.220` (veil cluster ingress)| none — already off-host              | needs `Host: stiletto-lite.veil.home.arpa` override    |
| `ntfy.valueof.info`         | `127.0.0.1:8090` on skaia             | bind ntfy to LAN IP                  | also update `custom.ntfy.baseUrl` consumers            |
| `trivia.valueof.info`       | `127.0.0.1:8765` on skaia (when on)   | `custom.trivia.listenAddress`        | service is usually off; vhost can still move           |
| `assistant.valueof.info`    | `assistant-direct.home.arpa:8123`     | none — already off-host (HA Yellow)  | rate-limit zones and fail2ban also live here           |
| `stream.valueof.info`       | `127.0.0.1:{1985,8086,8080}` on skaia | bind SRS + auth to LAN, OR move SRS  | plus separate UDP `8000` WebRTC forward; see below     |

LAN-only vhosts that **stay on skaia**:

- `forgejo.home.arpa` → `127.0.0.1:3044`
- `netdata.home.arpa` → `127.0.0.1:19999`
- `cache.home.arpa` → `127.0.0.1:5380`
- `ollama.home.arpa` → `127.0.0.1:11434`
- `assistant.home.arpa` → `assistant-direct.home.arpa:8123`

`ddclient` records currently published (`hosts/skaia/ddclient.nix`):
`@`, `teleport`, `urbit`, `stiletto-demo`, `stream`, `assistant`,
`ntfy`. Once hive owns the WAN IP for these records, the `ddclient`
config moves wholesale; cross-check whether `trivia` needs adding
(it isn't in the current list — likely covered by manual A record
or a CNAME chain through one of the others).

## Pre-flight decisions

### 1. Certificate continuity strategy

`security.acme` (Let's Encrypt) certificates live in
`/var/lib/acme/<fqdn>/` and are scoped to the host. After cutover
hive will need valid certs at first request. Three strategies:

- **A. rsync state then let hive renew.** Before flipping the
  router port forwards, `rsync -a /var/lib/acme/` from skaia to
  hive (root-owned, mode 0700; tarball it for safety). After the
  flip, hive's `acme-*` units own renewals. Cleanest, no
  Let's-Encrypt rate-limit exposure, ~5 minutes of work.

- **B. Switch to DNS-01.** Use the Namecheap dynamic-DNS account's
  general DNS API (not the dyn-DNS endpoint) to satisfy DNS-01
  challenges via `lego` / `cert-manager`'s namecheap provider.
  Decouples certs from port-forwards but adds a new credential
  and a new failure mode. **Defer** unless we plan to use DNS-01
  elsewhere; not worth introducing for this migration.

- **C. Cold-start from scratch on hive.** Stage hive with no certs
  and let it issue post-cutover. Cost: a window of no-TLS or
  invalid-cert public traffic while issuance happens, plus
  Let's-Encrypt's "5 duplicate certs per registered domain per
  week" budget if anything goes wrong and we re-issue. Avoid.

**Recommended: A.**

### 2. Backend rebinding strategy

For services that currently bind `127.0.0.1` on skaia and need to
be reachable from hive over the LAN:

- **ntfy**: `services.ntfy-sh.settings.listen-http` (or whatever
  upstream module key is exposed; module currently hard-codes
  the listener in `modules/ntfy.nix`, so a small option addition
  is needed). Bind to `0.0.0.0:8090` or skaia's LAN IP.
- **trivia**: `custom.trivia.listenAddress = "0.0.0.0"` already
  exposed; flip in `hosts/skaia/default.nix`.
- **Teleport**: `proxy_service.web_listen_addr` from
  `127.0.0.1:3080` to a LAN IP — but see carve-out.
- **SRS streaming**: harder, because the container binds to
  `127.0.0.1:*` explicitly in `hosts/skaia/streaming.nix`. Either
  (a) re-publish those ports to LAN, (b) move the container to
  hive, or (c) leave SRS on skaia and have hive's nginx proxy
  directly to `skaia.home.arpa`. Option (c) keeps the change
  surface small for the initial cutover.

For each rebind, **also tighten skaia's host firewall**: after
hive becomes the only legitimate client, allow only `hive`'s LAN
IP on each of those backend ports rather than the entire LAN.

### 3. Single-cutover vs. staged

A single cutover (all 8 vhosts at once, ~15 min downtime) is the
fastest path but a worse rollback story if any one vhost
misbehaves. A staged cutover moves vhosts in small batches:

- Batch 1 (no-risk): `valueof.info` static + `urbit.valueof.info`
  (upstream is already on hive).
- Batch 2: `stiletto.valueof.info`, `assistant.valueof.info`
  (both have off-host upstreams).
- Batch 3: `ntfy.valueof.info`, `trivia.valueof.info` (after
  backend rebinds land).
- Batch 4: `stream.valueof.info` — UDP 8000, the auth service,
  and container coordination make this the fiddliest one.
- Batch 5 (optional): `teleport.valueof.info` only after a
  Teleport-relocation decision (see below).

Staged makes more sense; batches 1+2 can happen in one short
cutover, the rest can each take their own micro-window.

### 4. Teleport carve-out

The full VPN-on-skaia goal requires that **no inbound public
traffic terminate on skaia**, because the asymmetric routing
problem applies to any response packet that has to traverse the
VPN tunnel. Teleport currently terminates **three** WAN ports on
skaia (`3023` proxy, `3024` reverse tunnel, `3026` kube proxy),
plus the HTTPS UI on `127.0.0.1:3080` (fronted by nginx). Moving
the nginx vhost for `teleport.valueof.info` alone is necessary
but not sufficient.

Options, in increasing scope:

- **T0: Defer.** Move only the nginx surface; leave Teleport on
  skaia. `skaia` keeps the `3023` / `3024` / `3026` port
  forwards. VPN-on-skaia still breaks Teleport SYN-ACK egress
  when VPN is up. Effectively, this runbook half-solves the
  ddclient race (because ddclient is no longer on skaia) but the
  symmetric VPN-as-default goal is unmet for Teleport sessions.
- **T1: Relocate Teleport's proxy + auth to hive.** Big lift:
  re-issue the host CA, re-enroll every node (re-mint join
  tokens for all `meteor-1..4` + skaia + hive), reissue user
  certs (`tsh login` re-auth), update `public_addr` /
  `tunnel_public_addr` to point at hive, repoint the kube
  service. **This deserves its own runbook**, not a section in
  this one.
- **T2: Use a network namespace on skaia.** Run ProtonVPN inside
  a netns and bind only browser/VPN-needy apps inside it
  (vopono-style); leave the default namespace's routing alone so
  Teleport + ddclient + any future server-side service on skaia
  keeps working. This is the smallest blast radius but flips the
  defaulting: "VPN as default for the workstation" becomes "VPN
  on demand inside a namespace", which is a regression from the
  user-experience goal.

**This runbook stays in T0 scope.** Teleport is left on skaia; we
explicitly call out the residual VPN-on-skaia limitation. When
you're ready to actually flip VPN to default, draft
`docs/runbooks/teleport-relocation.md` first.

## Phases

### Phase 1 — Config-only standby (no cutover)

Goal: hive is fully configured to take over the edge, but the
TP-Link router still forwards `80` / `443` to skaia. No DNS
flips, no port-forward flips. Everything is reversible by
`make apply-host HOST=hive` with the standby module removed.

1. **Add `hosts/hive/nginx.nix`** mirroring
   `hosts/skaia/nginx.nix`'s public-vhost set, with the
   following deltas:

   - `valueof.info` → embed/copy the static index file as
     `assets/valueof-info-index.html` (or keep the inline
     `writeTextFile` for now).
   - `teleport.valueof.info` → omit until Teleport is relocated
     (T1) or include it pointing at `skaia.home.arpa:3080`
     (T0 — Teleport's UI proxies through hive, but the gRPC
     ports `3023/3024` stay on skaia). T0 keeps it.
   - `urbit.valueof.info` → unchanged (`http://localhost:8080`
     since the upstream lives on hive itself now).
   - `stiletto.valueof.info` → unchanged.
   - `ntfy.valueof.info` → upstream becomes
     `http://skaia.home.arpa:8090` after the ntfy rebind.
   - `trivia.valueof.info` → upstream becomes
     `http://skaia.home.arpa:8765` after the trivia rebind.
   - `assistant.valueof.info` → upstream stays
     `http://assistant-direct.home.arpa:8123`.
   - `stream.valueof.info` → upstream becomes
     `http://skaia.home.arpa:{1985,8086,8080}` after the SRS
     rebind (or relocate the container).

   `enableACME = true` everywhere. Add the same
   `appendHttpConfig` rate-limit zones used on skaia.

1. **Add `hosts/hive/ddclient.nix`** copying skaia's verbatim,
   importing it from `hosts/hive/default.nix`. Move the
   `secrets/ddclient-password` entry into hive's per-host
   secrets manifest. Leave skaia's `ddclient` enabled for now —
   it'll race with hive briefly post-cutover, then we disable
   skaia's. (Both publishing the same WAN IP is harmless; the
   problem only arises when one of them publishes a wrong IP.)

1. **Open hive's firewall for `80` / `443`**. Add them to
   `hosts/hive/default.nix`'s `networking.firewall.allowedTCPPorts`.

1. **Plan backend rebinds (no flips yet).** In a single commit,
   add (but do not enable) the rebind hooks:

   - Extend `modules/ntfy.nix` with a `listenAddress` option
     defaulting to `127.0.0.1`; thread it into the existing
     listener.
   - `hosts/skaia/default.nix`: `custom.trivia.listenAddress`
     defaults to `127.0.0.1` (no change needed at this step).
   - `hosts/skaia/streaming.nix`: leave for Phase 2.

1. **Apply hive.** `make apply-host HOST=hive`. nginx comes up
   with all the vhosts but no public traffic hits them yet
   because the router is still pointing at skaia. ACME tries to
   issue but **will fail** because Let's Encrypt's HTTP-01
   challenge needs port `80` on the public IP, which still
   routes to skaia. Either:

   - Pre-stage the cert directories with rsync from skaia
     **right before Phase 2** so hive doesn't churn on failing
     ACME attempts in the meantime, or
   - Mark `enableACME = false` on every vhost in this commit
     and flip them all to `true` as part of Phase 2.

   The second option is cleaner — no half-attempted issuance,
   nothing in the ACME journal between Phase 1 and Phase 2.

1. **Sanity-check from the LAN.** Resolve
   `valueof.info` to hive's LAN IP via `/etc/hosts` or `curl
   --resolve` and confirm hive's nginx is willing to serve the
   right `Host:` headers (with self-signed certs at this stage,
   `curl -k`).

### Phase 2 — Cutover

Goal: switch the WAN edge from skaia to hive in a single
~10-15 minute window.

1. **Stop skaia's ddclient** so it stops trying to publish the
   home WAN IP under skaia's identity:

   ```sh
   ssh -t skaia.home.arpa 'sudo systemctl stop ddclient'
   ```

   (We'll remove it from skaia's config in Phase 3; stopping is
   enough for the cutover.)

1. **Land the backend rebinds.** In a single commit:

   - `modules/ntfy.nix`: set the new option to `0.0.0.0`
     (or skaia's LAN IP) in `hosts/skaia/default.nix`.
   - `hosts/skaia/default.nix`: set
     `custom.trivia.listenAddress = "0.0.0.0";`.
   - `hosts/skaia/streaming.nix`: change the container port
     bindings from `127.0.0.1:N:N` to `0.0.0.0:N:N` for ports
     `1985`, `8086`, `8080`. Confirm the `srs-auth` unit can be
     reached on a LAN IP.
   - Tighten skaia's firewall: drop the LAN-default-open posture
     for these ports and allow only `hive`'s LAN IP.

   Apply skaia: `make apply-host HOST=skaia`.

1. **rsync the ACME state** from skaia to hive:

   ```sh
   ssh skaia.home.arpa 'sudo tar -C /var/lib -czf /tmp/acme.tgz acme'
   scp skaia.home.arpa:/tmp/acme.tgz /tmp/acme.tgz
   scp /tmp/acme.tgz hive.home.arpa:/tmp/acme.tgz
   ssh -t hive.home.arpa '
     sudo systemctl stop nginx
     sudo rm -rf /var/lib/acme
     sudo tar -C /var/lib -xzf /tmp/acme.tgz
     sudo systemctl start nginx
   '
   ssh skaia.home.arpa 'rm /tmp/acme.tgz' || true
   ssh hive.home.arpa 'rm /tmp/acme.tgz'   || true
   ```

   (Yes, we run this with skaia still serving HTTPS — the rsync
   captures the current state; the cert is then a few seconds
   stale on hive at cutover, which is fine.)

1. **Flip `enableACME = true`** on hive's vhosts (if the cautious
   Phase-1 option was taken). Apply hive. nginx will pick up the
   rsynced certs without trying to re-issue (they're still
   valid) so the first ACME run on hive is just a no-op until
   renewal threshold.

1. **Flip the router port-forwards** on the TP-Link admin UI:
   change the `80` / `443` forward targets from skaia's LAN IP
   to hive's. (If keeping Teleport on skaia, leave `3023` /
   `3024` / `3026` on skaia.)

1. **Verify public connectivity.** From outside the LAN
   (phone hotspot, etc.):

   ```sh
   for h in valueof.info urbit.valueof.info ntfy.valueof.info \
            stiletto.valueof.info assistant.valueof.info \
            stream.valueof.info teleport.valueof.info; do
     echo "== $h =="
     curl -sI "https://$h/" | head -3
   done
   ```

   Each should return a `2xx` or `3xx`, with the issuer in the
   handshake matching the migrated Let's Encrypt chain.

1. **Verify ddclient on hive**:

   ```sh
   ssh hive.home.arpa 'sudo systemctl status ddclient'
   ssh hive.home.arpa 'sudo journalctl -u ddclient -n 50 --no-pager'
   ```

   Expect `SUCCESS: ... IP set to <wan-ip>` for each of the
   tracked subdomains.

### Phase 3 — Cleanup

1. **Remove skaia's nginx public vhosts** (keep only the
   `*.home.arpa` ones). Edit `hosts/skaia/nginx.nix` to drop the
   8 public vhosts; leave the LAN-only vhosts and the activation
   script for the trivia htpasswd in case the backend stays on
   skaia.

1. **Remove skaia's ddclient module** entirely
   (`hosts/skaia/ddclient.nix`), remove its import from
   `hosts/skaia/default.nix`, and drop the
   `secrets/ddclient-password` entry from skaia's per-host
   secrets manifest. The secret stays in the repo (it's
   per-account, not per-host).

1. **Tighten skaia's WAN firewall.** In
   `hosts/skaia/firewall.nix`, drop `80` and `443` from
   `allowedTCPPorts`. Keep `22`, the `3023..3026` Teleport range
   (if T0), and any service-internal LAN ports that need to
   stay reachable. Audit the spuriously-public ports while
   you're here (`53`, `6443`, `10250`, `19999`, `30400`, `3100`
   are LAN-only in spirit and should not be in the WAN-facing
   allow-list).

1. **Apply skaia + hive,** commit.

1. **Open follow-ups:** Decide on the Teleport carve-out (T0/T1/T2)
   and the SRS streaming relocation. Each gets its own runbook
   or extension to this one.

## Rollback

During Phase 2, **before** flipping the router port-forwards:
nothing is yet committed externally. Revert any Nix changes on
skaia/hive and apply.

**After** the router flip:

1. Flip the TP-Link forward back to skaia.
1. Start skaia's ddclient: `sudo systemctl start ddclient`.
1. If skaia's nginx vhosts were already removed in the same
   commit as the cutover (don't do this), `git revert` and
   `make apply-host HOST=skaia` to bring them back. The rsync'd
   ACME state on hive is harmless to leave.

Keep Phase 2 and Phase 3 as separate commits specifically so the
rollback for Phase 2 doesn't have to drag deletions back.

## Gotchas

- **ACME rate limits.** Let's Encrypt enforces 5 duplicate certs
  per registered domain per week. The `valueof.info` registered
  domain currently has 8 leaves. If a rough cutover triggers
  re-issuance for several of them in the same week, we can run
  the budget out. The rsync strategy avoids this entirely; the
  cold-start strategy is the risk.

- **The `recommendedProxySettings` Host header.** Several skaia
  vhosts (Forgejo, Ollama, Home Assistant, stiletto) deliberately
  bypass `proxyPass` and use raw `extraConfig` because the
  default `proxy_set_header Host $proxy_host` interacts badly
  with their upstreams. The same workarounds need to land on
  hive verbatim — don't rewrite the proxy stanzas.

- **HA's aiohttp Duplicate-Host trap.** Documented inline in
  `hosts/skaia/homeassistant.nix`: do not redeclare
  `proxy_set_header Host` inside `location` blocks after
  `recommendedProxySettings = true`. aiohttp ≥ 3.10 rejects with
  `400 Duplicate 'Host' header found.` This bit us during the
  2026.4.x upgrade and will bite again on the migrated vhost if
  the existing stanza is rewritten "cleaner".

- **Trivia htpasswd permissions.** `hosts/skaia/nginx.nix`'s
  `system.activationScripts.trivia-htpasswd-perms` runs on
  activation to chown the htpasswd to `root:nginx`. The
  equivalent activation script needs to land on hive too, and
  the secret needs to be present in hive's per-host secrets
  manifest.

- **SRS / UDP 8000.** Moving only the nginx vhost for
  `stream.valueof.info` is insufficient if the SRS container
  stays on skaia: the WHEP-published WebRTC media uses UDP 8000
  directly (advertised via the `candidate` field as
  `stream.valueof.info`). If ddclient now publishes the home WAN
  IP on hive's behalf but UDP 8000 is still forwarded to skaia,
  it should still work — UDP 8000 isn't TLS-terminated by nginx.
  But the moment skaia goes under VPN, those UDP responses get
  routed back through the tunnel and viewers see ICE failures.
  Streaming is the strongest argument for relocating SRS
  entirely to hive.

- **`hosts/skaia/firewall.nix` already has stale ports.** Several
  ports in the allow-list are LAN-only in intent (`53`, `6443`,
  `10250`, `19999`, `30400`, `3100`, `8200`, `9999`) but are
  declared in `allowedTCPPorts` rather than scoped to the LAN.
  Use this migration as the forcing function to clean that up.
  Document the audit in the commit message.

- **Hive becomes a SPOF for public traffic.** Today, skaia going
  down breaks public traffic too, so this isn't a regression in
  practice. But after the move, anything that crashes hive (a
  bad apply, a kernel oops, the new spinning-disk failure mode
  we just patched against) takes the whole public surface
  offline. The HA Yellow is its own physical box; nothing else
  is. If we ever want public-edge HA, the answer is probably
  routing through a small VPS rather than a redundant LAN host.

## Out-of-band caveats

- **TP-Link router admin UI** is the manual step. There's no
  programmatic interface; document the exact "Advanced → NAT
  Forwarding → Port Forwarding" path the operator clicks
  through, including a screenshot or the rule-table row layout
  before/after.
- **Public DNS A records.** ddclient updates the dynamic-DNS A
  records, but if any of these subdomains has a manually-managed
  A record (suspect `trivia`, since it isn't in the ddclient
  list), the operator has to flip those in the Namecheap admin
  UI by hand. Audit before the cutover.

## Open questions / follow-ups

- **When (and how) does Teleport move?** Drafting
  `docs/runbooks/teleport-relocation.md` is the prerequisite for
  the "VPN-as-default-on-skaia" goal actually being met.
- **Does SRS streaming move with the edge, or stay on skaia and
  rebind?** "Rebind" is the lower-friction default for this
  runbook, but the asymmetric-routing argument above pushes
  toward "move".
- **ntfy backend relocation.** The ntfy module is now reasonably
  self-contained (cache.db, attachments dir, an htpasswd-ish
  user file). It's a small enough lift that we could move ntfy
  *entirely* to hive in the same maintenance window as the edge
  move, simplifying the rebind step. Decision deferred.
- **Forgejo / harmonia / netdata.** All LAN-only today. Stay on
  skaia. If we ever want any of them publicly reachable, the
  hive nginx becomes the right place to add a vhost.

## Migration history

| Date | Phase 1 (standby) | Phase 2 (cutover) | Phase 3 (cleanup) | Notes |
|------|-------------------|-------------------|-------------------|-------|
| —    | —                 | —                 | —                 | not yet executed |

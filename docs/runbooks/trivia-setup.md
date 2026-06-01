# Trivia Drip-Release Server Setup

Prepare `trivia.valueof.info` for a one-evening contest: timed file
reveals via directory names, nginx Basic Auth, and a sandboxed FastAPI
app on `skaia`. The NixOS service, vhost, and sandbox are declarative;
this runbook covers the manual secret, TLS edge cases, smoke tests, and
round content staging.

## Prerequisites

- DNS A record for `trivia.valueof.info` pointing to the router WAN IP
- TCP 80/443 forwarded to `skaia` (see
  [Router port forwards](../COLD-START.md#router-port-forwards-for-skaia-ingress))
- GPG keys and `make reveal-secrets` working (see
  [GPG key setup](../COLD-START.md#gpg-key-setup-prerequisite-for-secrets))

## Steps

1. **Create the Basic Auth htpasswd file.** The credential gates the
   public vhost; share it with contestants alongside the event invite.

   ```sh
   # Use APR1/MD5 (-m), which nginx's auth_basic supports universally
   # via crypt(3). Bcrypt (-B) is NOT a safe choice here: nginx silently
   # treats unknown crypt formats as "no match", so a bcrypt htpasswd
   # produces "password mismatch" for every login attempt.
   #
   # No -b flag, so htpasswd prompts for the password and it stays out
   # of shell history. Pick a password long/random enough that 50
   # contestants can paste it without humans guessing it offline.
   nix-shell -p apacheHttpd --run \
     "htpasswd -cm secrets/trivia-htpasswd trivia"

   # Sanity check: the hash should start with $apr1$ (APR1 MD5).
   sed -n 's/.*://;p' secrets/trivia-htpasswd | head -c 6

   git secret add secrets/trivia-htpasswd
   git secret hide
   git add secrets/trivia-htpasswd.secret .gitignore
   ```

   The username is `trivia` here; pick something else if you prefer.
   To add more users, drop the `c` flag: `htpasswd -m secrets/...`.

1. **Deploy:**

   ```sh
   make reveal-secrets
   make apply-host HOST=skaia
   ```

   `systemd-tmpfiles` (via the `z` rule in `hosts/skaia/nginx.nix`) fixes
   ownership to `root:nginx` mode `0640` on every boot and rebuild so
   nginx workers can read the file — no manual chown needed. The rule is
   tolerant of the file's absence, so this also works on a fresh deploy
   before secrets have been revealed.

   If `acme-order-renew-trivia.valueof.info.service` fired before nginx
   was healthy on the same rebuild (e.g. the deploy hit a config error
   that took nginx down for the first few seconds), Let's Encrypt will
   have failed the HTTP-01 challenge and the timer won't retry for ~24h.
   Force a re-issue once nginx is up:

   ```sh
   sudo systemctl start acme-order-renew-trivia.valueof.info.service
   journalctl -u acme-order-renew-trivia.valueof.info.service -f
   ```

   Look for `Server responded with a certificate.` to confirm success.

1. **Smoke-test the deploy.** With `custom.trivia.seedFixtures = true`
   (current default in `hosts/skaia/default.nix`), the deploy populates
   `/var/lib/trivia/rounds/` with synthetic rounds — including
   intentionally invalid entries — so the parser can be exercised
   end-to-end:

   ```sh
   # Locally on skaia first
   curl -s http://127.0.0.1:8765/ | head

   # Through nginx + Basic Auth
   curl -i -u trivia:WRONG https://trivia.valueof.info/                # 401
   curl -i -u trivia:RIGHT https://trivia.valueof.info/                # 200
   curl -i -u trivia:RIGHT https://trivia.valueof.info/warmup/         # 200
   curl -i -u trivia:RIGHT https://trivia.valueof.info/warmup/welcome.pdf
   curl -i -u trivia:RIGHT https://trivia.valueof.info/round-late/     # 404
   curl -i -u trivia:RIGHT https://trivia.valueof.info/has-escape/escape.txt
   curl -i -u trivia:RIGHT https://trivia.valueof.info/dir-is-symlink/
   curl -i -u trivia:RIGHT https://trivia.valueof.info/has-dotfile/.secret
   ```

   The fixture seeder uses `+60 seconds` for one round, so refreshing
   the index immediately after deploy will show a "round-1" entry in
   "Upcoming" that moves to "Available" within a minute.

1. **Check the sandbox.** Land in the OK range (~2–3) for
   `systemd-analyze security`:

   ```sh
   systemd-analyze security trivia
   ```

1. **Stage real round content.** Once you're ready for the event:

   - Drop `custom.trivia.seedFixtures = false` (or delete the option)
     in `hosts/skaia/default.nix`. Re-apply. This stops the fixture
     seeder from running; existing fixture directories are left alone
     until you remove them.

   - Clear out the smoke-test rounds (on `skaia`):

     ```sh
     sudo rm -rf /var/lib/trivia/rounds/*
     ```

   - Create one directory per round, named with the local-time
     ISO-8601 reveal timestamp and a URL slug:

     ```sh
     sudo -u trivia mkdir -p \
       /var/lib/trivia/rounds/2026-06-07T19:00:00__round-1
     sudo -u trivia cp ./round-1-files/*.pdf \
       /var/lib/trivia/rounds/2026-06-07T19:00:00__round-1/
     ```

     Repeat per round. Slugs must match `[a-z0-9][a-z0-9-]*`; filenames
     must match `[A-Za-z0-9][A-Za-z0-9._-]*` (no dotfiles, no spaces).

## During the event

To slip a round later, rename its directory (no service restart; discovery
is per-request):

```sh
sudo -u trivia mv \
  /var/lib/trivia/rounds/2026-06-07T19:30:00__round-2 \
  /var/lib/trivia/rounds/2026-06-07T19:40:00__round-2
```

## In config

- `modules/trivia.nix` — service module, fixture seeder, options
- `modules/hardened-service.nix` — reusable sandbox preset
- `assets/trivia-server.py` — FastAPI app
- `hosts/skaia/nginx.nix` — `trivia.valueof.info` vhost, rate limit zones,
  htpasswd permission fixup
- `hosts/skaia/default.nix` — enables `custom.trivia`
- `secrets/trivia-htpasswd[.secret]` — Basic Auth credentials

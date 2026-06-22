# Guix Substitute Server Plan

## Assumptions

- Target host is `nero`, not the smaller `dnsseed` host, because Bitcoin Core
  Guix builds need disk and CPU.
- Start with Linux-only Bitcoin Core builds, not the default full
  cross-platform release build. The default includes macOS targets and requires
  SDK handling.
- Expose only HTTPS through Caddy. Keep `guix publish` bound to localhost.

## Implementation Plan

1. Add a small NixOS module, likely `hosts/guix-substitutes.nix`, and import it
   from `hosts/nero/default.nix`.

2. Enable Guix and `guix publish` with the NixOS 25.11 Guix module:

   ```nix
   services.guix = {
     enable = true;

     publish = {
       enable = true;
       port = 8181;
       extraArgs = [
         "--listen=127.0.0.1"
         "--cache=/var/cache/guix/publish"
         "--compression=zstd:6"
         "--ttl=30d"
         "--negative-ttl=1h"
         "--workers=4"
       ];
     };
   };
   ```

3. Put `/gnu/store` and publish/cache/build state on the large `nero` data disk,
   not accidentally on a small root filesystem. Since `nero` already has
   `/data`, either bind-mount `/data/gnu` to `/gnu` or add a dedicated `/gnu`
   filesystem if we want this cleaner long-term.

4. Put Caddy in front of `guix publish`:

   ```nix
   services.caddy.virtualHosts."guix.fish.foo".extraConfig = ''
     reverse_proxy 127.0.0.1:8181
   '';
   ```

   No new public port is needed because 80 and 443 are already open.

5. Manage the substitute signing key:

   - Short term: let `services.guix.publish.generateKeyPair = true` create
     `/etc/guix/signing-key.{pub,sec}`.
   - Immediately after first deployment, export `/etc/guix/signing-key.pub` and
     publish it at `https://guix.fish.foo/signing-key.pub`.
   - Before any rebuild/reinstall that could replace `/etc/guix`, move both
     signing key files into sops-nix as binary secrets and set:

     ```nix
     services.guix.publish.generateKeyPair = false;
     services.guix.publish.extraArgs = [
       "--public-key=/run/secrets/guix-signing-key.pub"
       "--private-key=/run/secrets/guix-signing-key.sec"
     ];
     ```

     This keeps client trust stable across host rebuilds.

6. Add a `guix-bitcoin-build` system user and state directories under
   `/data/guix-bitcoin`.

7. Add a systemd oneshot service that:

   - clones or updates `https://github.com/bitcoin/bitcoin`;
   - resets its managed checkout to `origin/master`;
   - runs Bitcoin Core's `./contrib/guix/guix-build`;
   - starts with `HOSTS=x86_64-linux-gnu`, capped `JOBS`, and shared
     `SOURCES_PATH` and `BASE_CACHE` under `/data/guix-bitcoin`.

8. Add a two-day build timer:

   ```nix
   systemd.timers.guix-bitcoin-build.timerConfig = {
     OnBootSec = "30m";
     OnUnitActiveSec = "2d";
     Persistent = true;
     RandomizedDelaySec = "1h";
   };
   ```

9. Do not enable aggressive Guix GC until we have explicit GC roots for the build
   outputs/store paths we intend to serve. Otherwise a successful build can be
   collected and disappear from the substitute server. After that, enable
   conservative GC with a free-space floor.

10. Defer Cuirass initially. There does not appear to be a NixOS
    `services.cuirass` option or `cuirass` package in the pinned nixpkgs, while
    Cuirass is a Guix-native service/package. A simple systemd timer is lower
    risk for the first version. Revisit Cuirass if we need build history, a web
    UI, queues, notifications, or multiple specs.

## Success Criteria

- `systemctl status guix-daemon guix-publish caddy` is clean.
- `curl https://guix.fish.foo/signing-key.pub` returns the Guix public key.
- A client can authorize that key, add `https://guix.fish.foo` to substitute
  URLs, and `guix weather` shows available substitutes.
- `systemctl start guix-bitcoin-build.service` completes once manually before
  enabling the timer.

## References Checked

- NixOS 25.11 `services.guix` module.
- GNU Guix `guix publish` documentation.
- Lovergine substitute server article.
- Bitcoin Core `contrib/guix` documentation.
- Cuirass documentation and nixpkgs package/module search results.

# Implementation Notes

## Serve pruned node data from nero

- Added a `nero`-specific Caddy route on `bitcoin.fish.foo` at
  `/pruned-840k/*`.
- The route uses `handle_path` so files under `/data/pruned-840k` are served
  without exposing the local directory name as part of the filesystem root.
- Kept this on the existing `bitcoin.fish.foo` virtual host to avoid requiring
  new DNS records or a separate certificate.

## Prewarm Guix substitute cache after Bitcoin Core builds

- Added a post-build prewarm step to `guix-bitcoin-build.service`.
- The step walks the full `guix gc --requisites` closure for every default
  Bitcoin Core Guix host profile and requests each local `.narinfo` until
  `guix publish` returns success.
- The publish cache uses `--cache-bypass-threshold=0` so warmup only advances
  when the item has actually been baked into the cache, preserving cached
  responses and progress bars for later clients.
- Negative TTL advertising is disabled so a client that races a cache miss does
  not cache a transient baking 404.
- A final `guix weather` pass through the same pinned Guix time-machine
  revision checks each host before `last-built-commit` is written.

## Put Anubis in front of Forgejo

- Added a `forgejo` Anubis instance on `nero` and left Forgejo bound to its
  existing localhost HTTP port.
- Caddy now proxies `code.fish.foo` to Anubis, while Anubis forwards accepted
  requests to Forgejo.
- Enabled Open Graph passthrough so link previews can keep working through the
  Anubis challenge layer.
- Configured Caddy to trust Cloudflare proxy ranges and pass the client IP from
  `CF-Connecting-IP` to Anubis as `X-Forwarded-For` and `X-Real-IP`, preserving
  Anubis' default JWT binding to the real client IP.
- Kept this scoped to Forgejo because the seed dump and Guix substitute
  endpoints are machine-consumed services and should not receive a browser
  proof-of-work challenge.

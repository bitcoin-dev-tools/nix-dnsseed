# Radicle Bitcoin Core Seed Setup

This server runs a Radicle seed node at `radicle.fish.foo` and is configured to
seed only the Bitcoin Core repository.

## Configuration Summary

- Host: `nero`
- Radicle DNS name: `radicle.fish.foo`
- Radicle node port: `8776/tcp`
- Private node key: `sops` secret `radicle-private-key`
- Public node key: configured in `hosts/radicle.nix`
- Seeding policy: selective, with unknown repositories blocked by default
- Bitcoin Core RID: generated on the first mirror run and stored at `/var/lib/radicle-mirror/bitcoin.rid`
- Bitcoin Core allow rule: applied by `radicle-mirror-bitcoin-core.service`
- Owner delegates: mirror bot and `did:key:z6MkminBAVqNKgPS7bT6HqDqbXaE31jqZ8p3eXMAC2czwHJn`
- Web UI: `https://radicle.fish.foo`, proxied by Caddy to `radicle-httpd`
- Mirror job: `radicle-mirror-bitcoin-core.service`, scheduled hourly by systemd timer

## 1. Generate The Radicle Node Identity

Generate the node identity on a machine with `rad` installed:

```bash
RAD_HOME=/tmp/radicle-seed rad auth --alias radicle.fish.foo
```

When prompted for a passphrase, press Enter to leave it empty. Seed nodes do not
normally need a passphrase.

Record the private key, public key, and node ID:

```bash
cat /tmp/radicle-seed/keys/radicle
cat /tmp/radicle-seed/keys/radicle.pub
RAD_HOME=/tmp/radicle-seed rad self --nid
```

The `rad self --nid` output is needed for DNS-SD.

## 2. Store The Private Key In Sops

Open the shared YAML secrets file:

```bash
sops secrets/secrets.yaml
```

Add this key, using the private key from step 1:

```yaml
radicle-private-key: |
  -----BEGIN OPENSSH PRIVATE KEY-----
  ...
  -----END OPENSSH PRIVATE KEY-----
```

Save and exit. Do not commit the plaintext private key anywhere else.

## 3. Configure The Public Key

Edit `hosts/radicle.nix` and replace:

```nix
publicKey = "/var/lib/radicle/keys/radicle.pub";
```

with the public key from step 1:

```nix
publicKey = "ssh-ed25519 ...";
```

The public key is not secret and can be committed.

## 4. Build The NixOS Configuration

Build the `nero` host:

```bash
nix build .#nixosConfigurations.nero.config.system.build.toplevel --show-trace
```

This should pass once `radicle-private-key` exists in `secrets/secrets.yaml`.

## 5. Configure DNS

Point `radicle.fish.foo` at the `nero` server:

```text
radicle.fish.foo.  A     157.180.56.194
```

Add Radicle DNS-SD records. Replace `<NODE_ID>` with the output of:

```bash
RAD_HOME=/tmp/radicle-seed rad self --nid
```

Records:

```text
seed._radicle-node._tcp.fish.foo.  3600  IN  SRV  32767 32767 8776 radicle.fish.foo.
seed._radicle-node._tcp.fish.foo.  3600  IN  TXT  "nid=<NODE_ID>"
_radicle-node._tcp.fish.foo.       3600  IN  PTR  seed._radicle-node._tcp.fish.foo.
```

## 6. Deploy

Deploy the `nero` host:

```bash
nixos-rebuild switch --flake .#nero --target-host root@nero
```

Alternatively, use the repo's `just switch` recipe if `hostname` and `target`
are set for `nero`.

## 7. Verify The Node

On the server:

```bash
systemctl status radicle-node
systemctl status radicle-httpd
systemctl status caddy
journalctl -u radicle-node -f
rad-system self --nid
rad-system node status
rad-system node config --addresses
```

From another machine:

```bash
nc -vz radicle.fish.foo 8776
curl -I https://radicle.fish.foo
```

## 8. Create The Bitcoin Core Radicle Repository

The mirror service creates the Radicle repository on first run, adds Will's DID
as a delegate, and stores the generated RID in:

```text
/var/lib/radicle-mirror/bitcoin.rid
```

Run it manually after deploy:

```bash
systemctl start radicle-mirror-bitcoin-core.service
journalctl -fu radicle-mirror-bitcoin-core.service
```

## 9. Verify That Only Bitcoin Core Is Allowed

After the first mirror run, the seed should allow the generated Bitcoin Core RID:

```bash
cat /var/lib/radicle-mirror/bitcoin.rid
rad-system seed
```

`rad-system seed` with no arguments should list only the explicit Bitcoin Core
allow policy. Because `hosts/radicle.nix` sets `seedingPolicy.default = "block"`,
unknown repositories remain blocked.

On a fresh seed node, this means only Bitcoin Core is served. If this node was
previously used to seed other repositories, remove those explicit policies with
`rad-system unseed <RID>`.

## 10. Useful Operations

Check the Radicle service:

```bash
systemctl status radicle-node
```

Follow logs:

```bash
journalctl -u radicle-node -f
```

Show node addresses:

```bash
rad-system node config --addresses
```

Show allowed repositories:

```bash
rad-system seed
```

Inspect the Bitcoin Core seed policy:

```bash
rad-system inspect "$(cat /var/lib/radicle-mirror/bitcoin.rid)" --policy
```

## 11. Bitcoin Core GitHub Mirror

The server also runs a separate local Radicle identity for mirroring
`https://github.com/bitcoin/bitcoin.git` into the Radicle repository. This keeps
the public seed identity separate from the identity that publishes mirror
updates.

Mirror state lives under:

```text
/var/lib/radicle-mirror
```

The mirror node listens only on localhost:

```text
127.0.0.1:8777
```

The mirror service does this:

1. Initializes a dedicated `bitcoin-core-mirror` Radicle identity if needed.
2. Clones `https://github.com/bitcoin/bitcoin.git` if needed.
3. Creates the Radicle repository on first run.
4. Adds Will's DID as a delegate with threshold `1`.
5. Stores the generated RID at `/var/lib/radicle-mirror/bitcoin.rid`.
6. Checks out `origin/master` exactly on every run.
7. Allows that RID on the public seed node.
8. Pushes `master` to the Radicle remote.
9. Announces the update to the public seed node.

The timer runs hourly:

```bash
systemctl status radicle-mirror-bitcoin-core.timer
```

Run a mirror sync manually:

```bash
systemctl start radicle-mirror-bitcoin-core.service
journalctl -fu radicle-mirror-bitcoin-core.service
```

Show the mirror identity DID:

```bash
sudo -u radicle-mirror RAD_HOME=/var/lib/radicle-mirror HOME=/var/lib/radicle-mirror rad self
```

Show the generated RID:

```bash
cat /var/lib/radicle-mirror/bitcoin.rid
```

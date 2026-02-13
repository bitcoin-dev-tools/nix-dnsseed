# nix-dnsseed

NixOS deployment for Bitcoin DNS seeders using [dnsseedrs](https://github.com/willcl-ark/dnsseedrs).

## Overview

This flake deploys a NixOS server running:

- **dnsseedrs** -- Bitcoin DNS seeder (mainnet + signet instances)
- **CoreDNS** -- forwards DNS queries to dnsseedrs, with a catch-all REFUSED zone
- **Caddy** -- HTTPS file server for seed dumps, with Cloudflare DNS ACME
- **Tor** and **I2P** -- SOCKS proxies for onion/i2p peer crawling

## How dnsseedrs is integrated

The [dnsseedrs flake](https://github.com/willcl-ark/dnsseedrs) provides a NixOS module and overlay. This flake imports both:

```nix
# flake.nix inputs
dnsseedrs.url = "github:willcl-ark/dnsseedrs";

# NixOS module configuration
modules = [
  inputs.dnsseedrs.nixosModules.default
  { nixpkgs.overlays = [ inputs.dnsseedrs.overlays.default ]; }
];
```

The overlay adds `pkgs.dnsseedrs` and the module provides `services.dnsseedrs.<name>` for declarative multi-instance configuration. Each instance gets its own systemd service and state directory at `/var/lib/dnsseedrs/<name>`.

## Secrets

Secrets are managed with [sops-nix](https://github.com/Mic92/sops-nix) and encrypted with age + PGP keys. The server decrypts at boot using an age key at `/var/lib/sops-nix/key.txt`.

Managed secrets:
- Cloudflare API token (for Caddy ACME DNS challenges)
- DNSSEC keys (ZSK + KSK per network, deployed as binary files)

## Usage

Requires [just](https://github.com/casey/just) and [nix](https://nixos.org/download/) with flakes enabled.

```bash
# First-time deploy via nixos-anywhere (wipes target disk)
just deploy

# Sync config and rebuild on the remote
just switch

# Build locally to check for errors
just build

# Tail service logs (defaults to mainnet)
just logs
just logs signet

# Update flake inputs
just update
```

### Initial setup

1. Deploy with `just deploy` (generates `hardware-configuration.nix` from the target)
2. Generate an age key on the server: `ssh root@dnsseed "mkdir -p /var/lib/sops-nix && age-keygen -o /var/lib/sops-nix/key.txt"`
3. Add the server's public key to `.sops.yaml` and re-encrypt all secrets:
   ```bash
   # The age-keygen output from step 2 prints the public key (age1...).
   # Add it as &server in .sops.yaml under the keys: section, and include
   # *server in each creation rule's age list.

   # Re-encrypt the YAML secrets
   sops updatekeys secrets/secrets.yaml

   # Re-encrypt the binary DNSSEC keys
   for f in secrets/dnssec/mainnet/K* secrets/dnssec/signet/K*; do
     sops updatekeys --input-type binary -y "$f"
   done
   ```
4. Apply with `just switch`

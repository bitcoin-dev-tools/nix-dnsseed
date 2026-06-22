set shell := ["bash", "-uc"]
hostname := "nero"
target := "root@nero"
ssh_port := env_var_or_default("SSH_PORT", "2222")

[private]
default:
    just --list

# Deploy NixOS via nixos-anywhere (first install)
deploy:
    #!/usr/bin/env bash
    set -euo pipefail
    key="keys/{{hostname}}.txt"
    if [[ ! -f "$key" ]]; then
        echo "Missing $key — run: just gen-key {{hostname}}" >&2
        exit 1
    fi
    pub=$(nix-shell -p age --run "age-keygen -y $key")
    if ! grep -qF "$pub" .sops.yaml; then
        echo "Pubkey $pub not in .sops.yaml — add it and run: just rekey" >&2
        exit 1
    fi
    stage=$(mktemp -d)
    trap "rm -rf $stage" EXIT
    install -D -m 400 "$key" "$stage/var/lib/sops-nix/key.txt"
    nix run github:nix-community/nixos-anywhere -- \
        --generate-hardware-config nixos-generate-config ./hosts/{{hostname}}/hardware-configuration.nix \
        --extra-files "$stage" \
        --flake .#{{hostname}} {{target}}

# Generate an age key for a host at keys/<host>.txt and print the pubkey.
gen-key host=hostname:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p keys
    key="keys/{{host}}.txt"
    if [[ -e "$key" ]]; then
        echo "Refusing to overwrite existing $key" >&2
        exit 1
    fi
    nix-shell -p age --run "age-keygen -o $key"
    chmod 400 "$key"
    pub=$(nix-shell -p age --run "age-keygen -y $key")
    echo
    echo "Add to .sops.yaml under 'keys:':"
    echo "  - &{{host}} $pub"
    echo "Reference *{{host}} in each creation_rules.age list, then run: just rekey"

# Re-encrypt every tracked secret to the recipients in .sops.yaml.
rekey:
    nix-shell -p sops --run "git ls-files secrets | xargs -n1 sops updatekeys -y"

# Sync repo to remote and switch configuration
switch:
    rsync -avz -e 'ssh -p {{ssh_port}}' --delete --exclude='.git' --filter=':- .gitignore' ./ {{target}}:/etc/nixos/
    ssh -p {{ssh_port}} {{target}} "git config --global --add safe.directory /etc/nixos && cd /etc/nixos && git init -q && git add -A && nixos-rebuild switch --flake /etc/nixos#{{hostname}}"

# Build locally and switch remote configuration
push:
    NIX_SSHOPTS='-p {{ssh_port}}' nixos-rebuild switch --flake .#{{hostname}} --target-host {{target}}

# Build configuration locally
build:
    nix build .#nixosConfigurations.{{hostname}}.config.system.build.toplevel --show-trace

# Update flake inputs
update:
    nix flake update

logs network="mainnet":
    ssh -p {{ssh_port}} {{target}} "systemctl status dnsseedrs-{{network}} && journalctl -f -u dnsseedrs-{{network}}"

# Report total node count in the dnsseedrs sqlite db
@db-stats network="mainnet":
    ssh -p {{ssh_port}} {{target}} "nix shell --quiet nixpkgs#sqlite -c sqlite3 /var/lib/dnsseedrs/{{network}}/sqlite.db 'SELECT COUNT(*) FROM nodes;'"

ssh:
    ssh -p {{ssh_port}} {{target}}

set shell := ["bash", "-uc"]
hostname := "nero"
target := "root@nero"

[private]
default:
    just --list

# Deploy NixOS via nixos-anywhere (first install)
deploy:
    nix run github:nix-community/nixos-anywhere -- \
        --generate-hardware-config nixos-generate-config ./hosts/{{hostname}}/hardware-configuration.nix \
        --flake .#{{hostname}} {{target}}

# Sync repo to remote and switch configuration
switch:
    rsync -avz --delete --exclude='.git' --filter=':- .gitignore' ./ {{target}}:/etc/nixos/
    ssh {{target}} "git config --global --add safe.directory /etc/nixos && cd /etc/nixos && git init -q && git add -A && nixos-rebuild switch --flake /etc/nixos#{{hostname}}"

# Build locally and switch remote configuration
push:
    nixos-rebuild switch --flake .#{{hostname}} --target-host {{target}}

# Build configuration locally
build:
    nix build .#nixosConfigurations.{{hostname}}.config.system.build.toplevel --show-trace

# Update flake inputs
update:
    nix flake update

logs network="mainnet":
    ssh {{target}} "systemctl status dnsseedrs-{{network}} && journalctl -f -u dnsseedrs-{{network}}"

ssh:
    ssh {{target}}

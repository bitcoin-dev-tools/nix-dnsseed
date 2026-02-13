set shell := ["bash", "-uc"]
hostname := "dnsseed"
target := "root@dnsseed"

[private]
default:
    just --list

# Deploy NixOS via nixos-anywhere (first install)
deploy:
    nix run github:nix-community/nixos-anywhere -- \
        --generate-hardware-config nixos-generate-config ./hosts/dnsseed/hardware-configuration.nix \
        --flake .#{{hostname}} {{target}}

# Sync repo to remote and switch configuration
switch:
    rsync -avz --delete --exclude='.git' --filter=':- .gitignore' ./ {{target}}:/etc/nixos/
    ssh {{target}} "git config --global --add safe.directory /etc/nixos && cd /etc/nixos && git init -q && git add -A && nixos-rebuild switch --flake /etc/nixos#{{hostname}}"

# Build configuration locally
build:
    nix build .#nixosConfigurations.{{hostname}}.config.system.build.toplevel --show-trace

# Update flake inputs
update:
    nix flake update

logs network="mainnet":
    ssh {{target}} "systemctl status dnsseedrs-{{network}} && journalctl -f -u dnsseedrs-{{network}}"

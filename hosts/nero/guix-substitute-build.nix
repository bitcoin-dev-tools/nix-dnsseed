{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.bitcoinCoreGuixSubstitutes;
  guixSystem = "x86_64-linux";
  profilesRoot = "${cfg.dataDir}/profiles/${guixSystem}";
  bitcoinGuixHosts = [
    "x86_64-linux-gnu"
    "arm-linux-gnueabihf"
    "aarch64-linux-gnu"
    "riscv64-linux-gnu"
    "powerpc64-linux-gnu"
    "x86_64-w64-mingw32"
    "x86_64-apple-darwin"
    "arm64-apple-darwin"
  ];
in
{
  systemd.services.guix-bitcoin-build = {
    description = lib.mkForce "Build Bitcoin Core Guix substitute profiles";
    script = lib.mkForce ''
      set -euo pipefail

      if [ ! -d ${cfg.dataDir}/bitcoin/.git ]; then
        git clone ${cfg.bitcoinRepository} ${cfg.dataDir}/bitcoin
      fi

      cd ${cfg.dataDir}/bitcoin
      git fetch ${cfg.bitcoinRemote} ${cfg.bitcoinBranch}
      commit="$(git rev-parse ${cfg.bitcoinRemote}/${cfg.bitcoinBranch})"
      git reset --hard ${cfg.bitcoinRemote}/${cfg.bitcoinBranch}

      mapfile -t manifests < <(
        find contrib/guix \
          -maxdepth 1 \
          -type f \
          -name 'manifest_*.scm' \
          -print \
          | sort
      )
      if [ "''${#manifests[@]}" -eq 0 ]; then
        echo "ERR: no contrib/guix/manifest_*.scm files found"
        exit 1
      fi

      JOBS=${toString cfg.buildJobs}
      ADDITIONAL_GUIX_COMMON_FLAGS=
      ADDITIONAL_GUIX_TIMEMACHINE_FLAGS="${cfg.additionalGuixTimemachineFlags}"
      SUBSTITUTE_URLS=
      source contrib/guix/libexec/prelude.bash

      profiles_dir=${profilesRoot}/"$commit"
      last_built=${cfg.dataDir}/last-built-manifests-${guixSystem}

      profiles_complete=true
      for host in ${lib.escapeShellArgs bitcoinGuixHosts}; do
        for manifest in "''${manifests[@]}"; do
          manifest_name="$(basename "$manifest" .scm)"
          if [ ! -e "$profiles_dir/$host/$manifest_name" ]; then
            profiles_complete=false
          fi
        done
      done

      if [ -f "$last_built" ] \
        && [ "$(cat "$last_built")" = "$commit" ] \
        && "$profiles_complete"; then
        echo "Bitcoin Core Guix manifests are already built at $commit; skipping."
        exit 0
      fi

      mkdir -p "$profiles_dir"

      materialize_profile() {
        host="$1"
        manifest="$2"
        profile="$3"

        if [ -e "$profile" ]; then
          return
        fi

        echo "Building $manifest profile for $host on ${guixSystem}..."
        HOST="$host" time-machine shell \
          --manifest="$manifest" \
          --cores=${toString cfg.buildJobs} \
          --keep-failed \
          --fallback \
          --root="$profile" \
          -- ${pkgs.coreutils}/bin/true
      }

      for host in ${lib.escapeShellArgs bitcoinGuixHosts}; do
        mkdir -p "$profiles_dir/$host"
        for manifest in "''${manifests[@]}"; do
          manifest_name="$(basename "$manifest" .scm)"
          materialize_profile \
            "$host" \
            "$manifest" \
            "$profiles_dir/$host/$manifest_name"
        done
      done

      prewarm_url=http://${cfg.publishAddress}:${toString cfg.publishPort}

      prewarm_store_path() {
        path="$1"
        hash="$(basename "$path" | cut -d- -f1)"
        until curl -fsS -o /dev/null "$prewarm_url/$hash.narinfo"; do
          sleep 10
        done
      }

      echo "Prewarming Guix substitute closure for ${guixSystem}..."
      for host in ${lib.escapeShellArgs bitcoinGuixHosts}; do
        for manifest in "''${manifests[@]}"; do
          manifest_name="$(basename "$manifest" .scm)"
          guix gc --requisites \
            "$(readlink -f "$profiles_dir/$host/$manifest_name")"
        done
      done | sort -u | while IFS= read -r path; do
        prewarm_store_path "$path"
      done

      check_manifest() {
        host="$1"
        manifest="$2"

        echo "Checking $manifest substitutes for $host on ${guixSystem}..."
        until HOST="$host" \
          time-machine weather \
            --substitute-urls="$prewarm_url" \
            --manifest="$manifest" \
          | grep -q '100.0% substitutes available'; do
          sleep 10
        done
      }

      for host in ${lib.escapeShellArgs bitcoinGuixHosts}; do
        for manifest in "''${manifests[@]}"; do
          check_manifest "$host" "$manifest"
        done
      done

      printf '%s\n' "$commit" > "$last_built"
    '';
  };

  systemd.services.guix-bitcoin-build-cleanup.script = lib.mkForce ''
    if [ -d ${profilesRoot} ]; then
      find ${profilesRoot} \
        -mindepth 1 \
        -maxdepth 1 \
        -type d \
        -mtime +${toString cfg.cleanup.maxAgeDays} \
        -exec rm -rf {} +
    fi

    find ${cfg.dataDir}/bitcoin \
      -maxdepth 1 \
      -type d \
      -name 'guix-build-*' \
      -mtime +${toString cfg.cleanup.maxAgeDays} \
      -exec rm -rf {} +
  '';
}

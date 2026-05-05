{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.services.bitcoinCoreGuixSubstitutes;

  runtimeDirectory = "guix-publish";
  runtimePath = "/run/${runtimeDirectory}";

  publicKeyRuntimePath = "${runtimePath}/signing-key.pub";
  privateKeyRuntimePath = "${runtimePath}/signing-key.sec";
  publicKeyWebPath = "${cfg.publicDirectory}/signing-key.pub";

  sdkSetup = lib.concatStringsSep "\n" (
    map (sdk: ''
      if [ ! -d ${cfg.stateDirectory}/macos-sdks/${sdk}-extracted-SDK-with-libcxx-headers ]; then
        curl -fL --retry 3 \
          ${cfg.macosSdkBaseUrl}/${sdk}-extracted-SDK-with-libcxx-headers.tar \
          -o ${cfg.stateDirectory}/macos-sdks/${sdk}-extracted-SDK-with-libcxx-headers.tar
        tar -C ${cfg.stateDirectory}/macos-sdks \
          -xaf ${cfg.stateDirectory}/macos-sdks/${sdk}-extracted-SDK-with-libcxx-headers.tar
      fi
    '') cfg.macosSdks
  );
in
{
  options.services.bitcoinCoreGuixSubstitutes = {
    enable = lib.mkEnableOption "Bitcoin Core Guix substitute server";

    domain = lib.mkOption {
      type = lib.types.str;
      description = "Public HTTPS domain for the substitute server.";
    };

    publishAddress = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      description = "Address guix publish listens on.";
    };

    publishPort = lib.mkOption {
      type = lib.types.port;
      default = 8181;
      description = "Port guix publish listens on.";
    };

    publishCacheDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/cache/guix/publish";
      description = "Directory used by guix publish for narinfo cache files.";
    };

    publicDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/guix-publish";
      description = "Directory served directly by Caddy for static public files.";
    };

    storeDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/gnu/store";
      description = "Guix store directory that must exist before guix-daemon starts.";
    };

    stateDirectory = lib.mkOption {
      type = lib.types.str;
      default = "/gnu/guix-bitcoin";
      description = "State directory for the Bitcoin Core checkout and Guix build caches.";
    };

    buildUser = lib.mkOption {
      type = lib.types.str;
      default = "guix-bitcoin-build";
      description = "System user that runs Bitcoin Core Guix builds.";
    };

    buildGroup = lib.mkOption {
      type = lib.types.str;
      default = "guix-bitcoin-build";
      description = "System group that runs Bitcoin Core Guix builds.";
    };

    signingKeySecrets = {
      public = lib.mkOption {
        type = lib.types.path;
        description = "Sops file containing the Guix substitute signing public key.";
      };

      private = lib.mkOption {
        type = lib.types.path;
        description = "Sops file containing the Guix substitute signing private key.";
      };
    };

    bitcoinRepository = lib.mkOption {
      type = lib.types.str;
      default = "https://github.com/bitcoin/bitcoin";
      description = "Bitcoin Core Git repository to build.";
    };

    bitcoinRemote = lib.mkOption {
      type = lib.types.str;
      default = "origin";
      description = "Remote name used for the Bitcoin Core checkout.";
    };

    bitcoinBranch = lib.mkOption {
      type = lib.types.str;
      default = "master";
      description = "Branch to build from the Bitcoin Core repository.";
    };

    buildJobs = lib.mkOption {
      type = lib.types.ints.positive;
      default = 16;
      description = "JOBS value passed to contrib/guix/guix-build.";
    };

    macosSdks = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "macOS SDK archives to download before running Guix builds.";
    };

    macosSdkBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://bitcoincore.org/depends-sources/sdks";
      description = "Base URL for Bitcoin Core macOS SDK archives.";
    };

    additionalGuixTimemachineFlags = lib.mkOption {
      type = lib.types.str;
      default = "--url=https://github.com/Millak/guix.git";
      description = "Flags passed through ADDITIONAL_GUIX_TIMEMACHINE_FLAGS.";
    };

    buildTimer = {
      onBootSec = lib.mkOption {
        type = lib.types.str;
        default = "30m";
        description = "Delay before the first scheduled Bitcoin Core Guix build.";
      };

      onUnitActiveSec = lib.mkOption {
        type = lib.types.str;
        default = "2d";
        description = "Interval between scheduled Bitcoin Core Guix builds.";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Randomized delay for scheduled Bitcoin Core Guix builds.";
      };
    };

    cleanup = {
      maxAgeDays = lib.mkOption {
        type = lib.types.ints.positive;
        default = 14;
        description = "Age in days after which guix-build-* work directories are removed.";
      };

      randomizedDelaySec = lib.mkOption {
        type = lib.types.str;
        default = "1h";
        description = "Randomized delay for the cleanup timer.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets."guix-signing-key.pub" = {
      sopsFile = cfg.signingKeySecrets.public;
      format = "binary";
      owner = "guix-publish";
      group = "guix-publish";
      mode = "0444";
    };
    sops.secrets."guix-signing-key.sec" = {
      sopsFile = cfg.signingKeySecrets.private;
      format = "binary";
      owner = "guix-publish";
      group = "guix-publish";
      mode = "0400";
    };

    services.guix = {
      enable = true;

      publish = {
        enable = true;
        generateKeyPair = false;
        port = cfg.publishPort;
        extraArgs = [
          "--listen=${cfg.publishAddress}"
          "--cache=${cfg.publishCacheDirectory}"
          "--compression=zstd:6"
          "--ttl=30d"
          "--negative-ttl=1h"
          "--workers=4"
          "--public-key=${publicKeyRuntimePath}"
          "--private-key=${privateKeyRuntimePath}"
        ];
      };
    };

    services.caddy.virtualHosts.${cfg.domain}.extraConfig = ''
      handle /signing-key.pub {
        root * ${cfg.publicDirectory}
        file_server
      }

      handle {
        reverse_proxy ${cfg.publishAddress}:${toString cfg.publishPort}
      }
    '';

    users.users.${cfg.buildUser} = {
      isSystemUser = true;
      group = cfg.buildGroup;
      home = cfg.stateDirectory;
      createHome = true;
    };
    users.groups.${cfg.buildGroup} = { };

    systemd.tmpfiles.rules = [
      "d ${cfg.storeDirectory} 0755 root root -"
      "d ${cfg.publishCacheDirectory} 0755 guix-publish guix-publish -"
      "d ${cfg.publicDirectory} 0755 root root -"
      "d ${cfg.stateDirectory} 0750 ${cfg.buildUser} ${cfg.buildGroup} -"
      "d ${cfg.stateDirectory}/bitcoin 0750 ${cfg.buildUser} ${cfg.buildGroup} -"
      "d ${cfg.stateDirectory}/cache 0750 ${cfg.buildUser} ${cfg.buildGroup} -"
      "d ${cfg.stateDirectory}/macos-sdks 0750 ${cfg.buildUser} ${cfg.buildGroup} -"
      "d ${cfg.stateDirectory}/sources 0750 ${cfg.buildUser} ${cfg.buildGroup} -"
    ];

    systemd.services.guix-publish = {
      after = [ "sops-install-secrets.service" ];
      wants = [ "sops-install-secrets.service" ];
      serviceConfig.ExecStartPre = [
        "+${pkgs.coreutils}/bin/install -d -m 0755 -o guix-publish -g guix-publish ${cfg.publishCacheDirectory}"
        "+${pkgs.coreutils}/bin/install -d -m 0755 -o root -g root ${cfg.publicDirectory}"
        "+${pkgs.coreutils}/bin/install -d -m 0750 -o guix-publish -g guix-publish ${runtimePath}"
        "+${pkgs.coreutils}/bin/install -m 0444 -o guix-publish -g guix-publish ${
          config.sops.secrets."guix-signing-key.pub".path
        } ${publicKeyRuntimePath}"
        "+${pkgs.coreutils}/bin/install -m 0444 -o root -g root ${
          config.sops.secrets."guix-signing-key.pub".path
        } ${publicKeyWebPath}"
        "+${pkgs.coreutils}/bin/install -m 0440 -o root -g guix-publish ${
          config.sops.secrets."guix-signing-key.sec".path
        } ${privateKeyRuntimePath}"
      ];
      serviceConfig.RuntimeDirectory = runtimeDirectory;
      serviceConfig.RuntimeDirectoryMode = "0750";
    };

    systemd.services.guix-bitcoin-build = {
      description = "Build Bitcoin Core with Guix";
      after = [
        "network-online.target"
        "guix-daemon.service"
      ];
      wants = [
        "network-online.target"
        "guix-daemon.service"
      ];
      path = [
        pkgs.bash
        pkgs.coreutils
        pkgs.curl
        pkgs.findutils
        pkgs.getent
        pkgs.gnumake
        pkgs.gnused
        pkgs.gnutar
        config.services.guix.package
        pkgs.git
      ];
      script = ''
        set -euo pipefail

        if [ ! -d ${cfg.stateDirectory}/bitcoin/.git ]; then
          git clone ${cfg.bitcoinRepository} ${cfg.stateDirectory}/bitcoin
        fi

        cd ${cfg.stateDirectory}/bitcoin
        git fetch ${cfg.bitcoinRemote} ${cfg.bitcoinBranch}
        commit="$(git rev-parse ${cfg.bitcoinRemote}/${cfg.bitcoinBranch})"
        if [ -f ${cfg.stateDirectory}/last-built-commit ] \
          && [ "$(cat ${cfg.stateDirectory}/last-built-commit)" = "$commit" ]; then
          echo "Bitcoin Core ${cfg.bitcoinBranch} is already built at $commit; skipping."
          exit 0
        fi

        git reset --hard ${cfg.bitcoinRemote}/${cfg.bitcoinBranch}
        git submodule update --init --recursive

        ${sdkSetup}

        JOBS=${toString cfg.buildJobs} \
        SOURCES_PATH=${cfg.stateDirectory}/sources \
        BASE_CACHE=${cfg.stateDirectory}/cache \
        SDK_PATH=${cfg.stateDirectory}/macos-sdks \
        ADDITIONAL_GUIX_TIMEMACHINE_FLAGS="${cfg.additionalGuixTimemachineFlags}" \
          ./contrib/guix/guix-build

        printf '%s\n' "$commit" > ${cfg.stateDirectory}/last-built-commit
      '';
      serviceConfig = {
        Type = "oneshot";
        User = cfg.buildUser;
        Group = cfg.buildGroup;
        ExecStartPre = [
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.buildUser} -g ${cfg.buildGroup} ${cfg.stateDirectory}"
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.buildUser} -g ${cfg.buildGroup} ${cfg.stateDirectory}/bitcoin"
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.buildUser} -g ${cfg.buildGroup} ${cfg.stateDirectory}/cache"
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.buildUser} -g ${cfg.buildGroup} ${cfg.stateDirectory}/macos-sdks"
          "+${pkgs.coreutils}/bin/install -d -m 0750 -o ${cfg.buildUser} -g ${cfg.buildGroup} ${cfg.stateDirectory}/sources"
        ];
      };
    };

    systemd.timers.guix-bitcoin-build = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = cfg.buildTimer.onBootSec;
        OnUnitActiveSec = cfg.buildTimer.onUnitActiveSec;
        Persistent = true;
        RandomizedDelaySec = cfg.buildTimer.randomizedDelaySec;
      };
    };

    systemd.services.guix-bitcoin-build-cleanup = {
      description = "Clean old Bitcoin Core Guix build work directories";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.buildUser;
        Group = cfg.buildGroup;
      };
      path = [
        pkgs.findutils
      ];
      script = ''
        find ${cfg.stateDirectory}/bitcoin \
          -maxdepth 1 \
          -type d \
          -name 'guix-build-*' \
          -mtime +${toString cfg.cleanup.maxAgeDays} \
          -exec rm -rf {} +
      '';
    };

    systemd.timers.guix-bitcoin-build-cleanup = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "daily";
        Persistent = true;
        RandomizedDelaySec = cfg.cleanup.randomizedDelaySec;
      };
    };
  };
}

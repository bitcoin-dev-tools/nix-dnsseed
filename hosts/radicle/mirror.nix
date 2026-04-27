{ config, pkgs, ... }:
let
  willDid = "did:key:z6MkminBAVqNKgPS7bT6HqDqbXaE31jqZ8p3eXMAC2czwHJn";
  seedNodeNid = "z6MkqUWxg7edhgBufSVEb39cEmndNEg8FuMhqCKaMB85UXDJ";
  radSystem = pkgs.writeShellScript "rad-system" ''
    set -o allexport
    HOME=/var/lib/radicle
    RAD_HOME=/var/lib/radicle
    exec ${pkgs.util-linux}/bin/nsenter -a \
      -t "$(${config.systemd.package}/bin/systemctl show -P MainPID radicle-node.service)" \
      -S "$(${config.systemd.package}/bin/systemctl show -P UID radicle-node.service)" \
      -G "$(${config.systemd.package}/bin/systemctl show -P GID radicle-node.service)" \
      ${config.services.radicle.package}/bin/rad "$@"
  '';
  mirrorEnv = {
    HOME = "/var/lib/radicle-mirror";
    RAD_HOME = "/var/lib/radicle-mirror";
  };
  mirrorInit = pkgs.writeShellScript "radicle-mirror-init" ''
    set -euo pipefail

    if [[ ! -f "$RAD_HOME/config.json" ]]; then
      printf '\n' | ${config.services.radicle.package}/bin/rad auth \
        --alias bitcoin-core-mirror \
        --stdin
    fi
  '';
  mirrorClone = pkgs.writeShellScript "radicle-mirror-clone" ''
    set -euo pipefail

    repo="$RAD_HOME/bitcoin"
    rid_file="$RAD_HOME/bitcoin.rid"

    if [[ ! -d "$repo/.git" ]]; then
      ${pkgs.git}/bin/git clone https://github.com/bitcoin/bitcoin.git "$repo"
      cd "$repo"
      ${config.services.radicle.package}/bin/rad init \
        --name bitcoin \
        --description "Bitcoin Core GitHub mirror" \
        --default-branch master \
        --scope followed \
        --public \
        --set-upstream \
        --no-confirm
      rid="$(${config.services.radicle.package}/bin/rad .)"
      printf '%s\n' "$rid" > "$rid_file"
      ${config.services.radicle.package}/bin/rad id update \
        --title "Add Will as mirror delegate" \
        --delegate ${willDid} \
        --threshold 1 \
        --no-confirm
    elif [[ ! -f "$rid_file" ]]; then
      cd "$repo"
      ${config.services.radicle.package}/bin/rad . > "$rid_file"
    fi
  '';
  mirrorUpdate = pkgs.writeShellScript "radicle-mirror-update" ''
    set -euo pipefail

    repo="$RAD_HOME/bitcoin"

    cd "$repo"
    if ${pkgs.git}/bin/git remote get-url origin >/dev/null 2>&1; then
      ${pkgs.git}/bin/git remote set-url origin https://github.com/bitcoin/bitcoin.git
    else
      ${pkgs.git}/bin/git remote add origin https://github.com/bitcoin/bitcoin.git
    fi
    ${pkgs.git}/bin/git fetch --prune --tags origin '+refs/heads/*:refs/remotes/origin/*'
    ${pkgs.git}/bin/git checkout -B master origin/master
    ${pkgs.git}/bin/git push rad master -o sync
  '';
  mirrorSeed = pkgs.writeShellScript "radicle-mirror-seed" ''
    set -euo pipefail

    rid="$(cat /var/lib/radicle-mirror/bitcoin.rid)"
    ${radSystem} seed "$rid"
  '';
  mirrorSync = pkgs.writeShellScript "radicle-mirror-sync" ''
    set -euo pipefail

    rid="$(cat "$RAD_HOME/bitcoin.rid")"
    ${config.services.radicle.package}/bin/rad node connect ${seedNodeNid}@127.0.0.1:8776 || true
    ${config.services.radicle.package}/bin/rad sync \
      --announce \
      --seed ${seedNodeNid} \
      --replicas 1 \
      --timeout 600s \
      "$rid"
  '';
in
{
  users.users.radicle-mirror = {
    description = "Radicle Bitcoin Core mirror";
    group = "radicle-mirror";
    home = mirrorEnv.HOME;
    isSystemUser = true;
  };
  users.groups.radicle-mirror = { };

  systemd.services.radicle-mirror-init = {
    description = "Initialize the Radicle Bitcoin Core mirror identity";
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      User = "radicle-mirror";
      Group = "radicle-mirror";
      StateDirectory = "radicle-mirror";
      StateDirectoryMode = "0750";
      WorkingDirectory = mirrorEnv.HOME;
      ExecStart = mirrorInit;
    };
    environment = mirrorEnv;
  };

  systemd.services.radicle-mirror-node = {
    description = "Radicle Bitcoin Core mirror node";
    after = [
      "network-online.target"
      "radicle-mirror-init.service"
    ];
    requires = [ "radicle-mirror-init.service" ];
    wants = [ "network-online.target" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${config.services.radicle.package}/bin/radicle-node --force --listen 127.0.0.1:8777";
      Restart = "on-failure";
      RestartSec = "30";
      User = "radicle-mirror";
      Group = "radicle-mirror";
      StateDirectory = "radicle-mirror";
      StateDirectoryMode = "0750";
      WorkingDirectory = mirrorEnv.HOME;
    };
    environment = mirrorEnv;
  };

  systemd.services.radicle-mirror-clone = {
    description = "Clone bitcoin/bitcoin and initialize its Radicle mirror";
    after = [
      "network-online.target"
      "radicle-mirror-node.service"
    ];
    requires = [ "radicle-mirror-node.service" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.git
      config.services.radicle.package
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "radicle-mirror";
      Group = "radicle-mirror";
      StateDirectory = "radicle-mirror";
      StateDirectoryMode = "0750";
      WorkingDirectory = mirrorEnv.HOME;
      ExecStart = mirrorClone;
    };
    environment = mirrorEnv;
  };

  systemd.services.radicle-mirror-update = {
    description = "Update the Bitcoin Core Git mirror";
    after = [
      "network-online.target"
      "radicle-mirror-clone.service"
    ];
    requires = [ "radicle-mirror-clone.service" ];
    wants = [ "network-online.target" ];
    path = [
      pkgs.git
      config.services.radicle.package
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "radicle-mirror";
      Group = "radicle-mirror";
      StateDirectory = "radicle-mirror";
      StateDirectoryMode = "0750";
      WorkingDirectory = mirrorEnv.HOME;
      ExecStart = mirrorUpdate;
    };
    environment = mirrorEnv;
  };

  systemd.services.radicle-mirror-seed = {
    description = "Allow the Bitcoin Core mirror RID on the public Radicle seed";
    after = [
      "radicle-node.service"
      "radicle-mirror-clone.service"
    ];
    requires = [
      "radicle-node.service"
      "radicle-mirror-clone.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = mirrorSeed;
    };
  };

  systemd.services.radicle-mirror-sync = {
    description = "Announce the Bitcoin Core Radicle mirror to the public seed";
    after = [
      "radicle-mirror-node.service"
      "radicle-mirror-update.service"
      "radicle-mirror-seed.service"
    ];
    requires = [
      "radicle-mirror-node.service"
      "radicle-mirror-update.service"
      "radicle-mirror-seed.service"
    ];
    serviceConfig = {
      Type = "oneshot";
      User = "radicle-mirror";
      Group = "radicle-mirror";
      StateDirectory = "radicle-mirror";
      StateDirectoryMode = "0750";
      WorkingDirectory = mirrorEnv.HOME;
      ExecStart = mirrorSync;
    };
    environment = mirrorEnv;
  };

  systemd.services.radicle-mirror-bitcoin-core = {
    description = "Mirror bitcoin/bitcoin into Radicle";
    after = [ "radicle-mirror-sync.service" ];
    requires = [ "radicle-mirror-sync.service" ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.coreutils}/bin/true";
    };
  };

  systemd.timers.radicle-mirror-bitcoin-core = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "10min";
      OnUnitActiveSec = "1h";
      Persistent = true;
    };
  };
}

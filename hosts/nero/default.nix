{ config, ... }:
{
  imports = [
    ../common.nix
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "nero";
  networking.useDHCP = true;

  services.dnsseedrs.mainnet = {
    enable = true;
    threads = 32;
  };
  services.dnsseedrs.signet = {
    enable = false;
    threads = 10;
  };

  sops.secrets.radicle-private-key = {
    owner = "radicle";
    group = "radicle";
    mode = "0400";
  };

  services.radicleMirror = {
    enable = true;
    domain = "radicle.fish.foo";

    seed = {
      enable = true;
      privateKeyFile = config.sops.secrets.radicle-private-key.path;
      publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPDAHBnAYYRqKFeDBC7VhYa4e6KbIV0VXdW6Bk1QMxZ radicle";
      nodeId = "z6MkqUWxg7edhgBufSVEb39cEmndNEg8FuMhqCKaMB85UXDJ";
    };

    frontend.enable = true;

    bitcoinMirror = {
      enable = true;
      delegateDids = [ "did:key:z6MkminBAVqNKgPS7bT6HqDqbXaE31jqZ8p3eXMAC2czwHJn" ];
    };
  };

  services.bitcoinCoreGuixSubstitutes = {
    enable = true;
    domain = "guix.fish.foo";
    stateDirectory = "/gnu/guix-bitcoin";

    signingKeySecrets = {
      public = ../../secrets/guix/signing-key.pub;
      private = ../../secrets/guix/signing-key.sec;
    };
    signingKeySignature = ../../secrets/guix/signing-key.pub.asc;

    macosSdks = [
      "Xcode-26.1.1-17B100"
    ];
  };

  systemd.services.radicle-node = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
}

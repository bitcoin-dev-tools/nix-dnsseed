{ config, ... }:
{
  imports = [
    ../common.nix
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "nero";
  networking.useDHCP = true;
  networking.interfaces.enp6s0.ipv6.addresses = [
    {
      address = "2a01:4f9:3100:441f::1";
      prefixLength = 64;
    }
  ];
  networking.defaultGateway6 = {
    address = "fe80::1";
    interface = "enp6s0";
  };

  services.bitcoinDnsSeed.mainnet = {
    enable = true;
    threads = 32;
  };
  services.bitcoinDnsSeed.signet = {
    enable = false;
    threads = 10;
  };

  services.stuntman.enable = true;

  services.openssh.ports = [
    22
    2222
  ];
  services.openssh.extraConfig = ''
    Match LocalPort 22
      DenyUsers root
  '';
  networking.firewall.allowedTCPPorts = [ 2222 ];

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
    dataDir = "/gnu/guix-bitcoin";

    signingKey = {
      publicFile = ../../secrets/guix/signing-key.pub;
      privateFile = ../../secrets/guix/signing-key.sec;
      signatureFile = ../../secrets/guix/signing-key.pub.asc;
    };

    macosSdks = [
      "Xcode-26.1.1-17B100"
    ];
  };

  services.forgejoSite = {
    enable = true;
    domain = "code.fish.foo";

    admin = {
      user = "willcl-ark";
      email = "will@256k1.dev";
    };

    mailer = {
      enable = true;
      from = "Forgejo <forgejo@fish.foo>";
      smtpAddress = "smtp.mailbox.org";
      user = "will@256k1.dev";
    };
  };

  services.caddy.virtualHosts."bitcoin.fish.foo".extraConfig = ''
    redir /pruned-840k /pruned-840k/
    handle_path /pruned-840k/* {
      root * /data/pruned-840k
      file_server browse
    }
  '';

  systemd.services.radicle-node = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
}

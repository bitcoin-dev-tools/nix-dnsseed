{
  config,
  lib,
  pkgs,
  ...
}:
let
  caddyWithCloudflare = pkgs.caddy.withPlugins {
    plugins = [ "github.com/caddy-dns/cloudflare@v0.2.3" ];
    hash = "sha256-/ooi0fP9zYzNnafaQqMnr6RmGh2onHrxDWiLE/aYNKI=";
  };

in
{
  boot.loader.grub = {
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # resolved is disabled (conflicts with CoreDNS on ports 53 and 5353),
  # so we need explicit nameservers in /etc/resolv.conf for outbound resolution.
  networking.nameservers = [
    "1.1.1.1"
    "8.8.8.8"
  ];
  # systemd-resolved binds port 53 (stub listener) and 5353 (mDNS), both of
  # which conflict with CoreDNS and dnsseedrs. Disabling it entirely is simpler
  # than trying to disable individual listeners.
  services.resolved.enable = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = false;
  };

  # sops-nix creates secret directories owned by root:keys — dnsseedrs needs
  # group membership to traverse them and read its DNSSEC key files.
  # The user/group are also declared by the dnsseedrs module when any instance
  # is enabled; declare them here so sops secret ownership resolves even when
  # all instances are disabled on a host.
  users.users.dnsseedrs = {
    isSystemUser = true;
    group = "dnsseedrs";
    extraGroups = [ "keys" ];
  };
  users.groups.dnsseedrs = { };

  users.users.root.openssh.authorizedKeys.keys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIH988C5DbEPHfoCphoW23MWq9M6fmA4UTXREiZU0J7n0 will.hetzner@temp.com"
  ];

  sops = {
    defaultSopsFile = ../secrets/secrets.yaml;
    age.keyFile = "/var/lib/sops-nix/key.txt";

    secrets.cloudflare-api-token = { };

    secrets."dnssec-mainnet/Kseed.bitcoin.fish.foo.+013+00562.key" = {
      sopsFile = ../secrets/dnssec/mainnet/Kseed.bitcoin.fish.foo.+013+00562.key;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };
    secrets."dnssec-mainnet/Kseed.bitcoin.fish.foo.+013+00562.private" = {
      sopsFile = ../secrets/dnssec/mainnet/Kseed.bitcoin.fish.foo.+013+00562.private;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };
    secrets."dnssec-mainnet/Kseed.bitcoin.fish.foo.+013+42136.key" = {
      sopsFile = ../secrets/dnssec/mainnet/Kseed.bitcoin.fish.foo.+013+42136.key;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };
    secrets."dnssec-mainnet/Kseed.bitcoin.fish.foo.+013+42136.private" = {
      sopsFile = ../secrets/dnssec/mainnet/Kseed.bitcoin.fish.foo.+013+42136.private;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };

    secrets."dnssec-signet/Kseed.signet.bitcoin.fish.foo.+013+15250.key" = {
      sopsFile = ../secrets/dnssec/signet/Kseed.signet.bitcoin.fish.foo.+013+15250.key;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };
    secrets."dnssec-signet/Kseed.signet.bitcoin.fish.foo.+013+15250.private" = {
      sopsFile = ../secrets/dnssec/signet/Kseed.signet.bitcoin.fish.foo.+013+15250.private;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };
    secrets."dnssec-signet/Kseed.signet.bitcoin.fish.foo.+013+32912.key" = {
      sopsFile = ../secrets/dnssec/signet/Kseed.signet.bitcoin.fish.foo.+013+32912.key;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };
    secrets."dnssec-signet/Kseed.signet.bitcoin.fish.foo.+013+32912.private" = {
      sopsFile = ../secrets/dnssec/signet/Kseed.signet.bitcoin.fish.foo.+013+32912.private;
      format = "binary";
      owner = "dnsseedrs";
      group = "dnsseedrs";
    };

    # Caddy needs the Cloudflare token as an env var for ACME DNS challenges.
    # sops.templates creates a KEY=VALUE file that systemd reads via EnvironmentFile.
    templates."caddy-env".content = ''
      CLOUDFLARE_API_TOKEN=${config.sops.placeholder."cloudflare-api-token"}
    '';
  };

  services.tor = {
    enable = true;
    client.enable = true;
  };

  services.i2pd = {
    enable = true;
    proto.socksProxy.enable = true;
  };

  # i2pd reseeds via HTTPS on first start; without network-online ordering it
  # races DNS, all reseed hosts fail, and it never retries — leaving netDb empty.
  systemd.services.i2pd = {
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
  };

  services.caddy = {
    enable = true;
    package = caddyWithCloudflare;
    globalConfig = ''
      acme_dns cloudflare {$CLOUDFLARE_API_TOKEN}
    '';
    # Serve seed dumps directly from dnsseedrs state directories.
    # hide *.db prevents the sqlite database from being listed or downloaded.
    virtualHosts."bitcoin.fish.foo".extraConfig = ''
      root * /var/lib/dnsseedrs/mainnet
      file_server browse {
        hide *.db
        hide sqlite*
      }
    '';
    virtualHosts."signet.bitcoin.fish.foo".extraConfig = ''
      root * /var/lib/dnsseedrs/signet
      file_server browse {
        hide *.db
        hide sqlite*
      }
    '';
  };

  systemd.services.caddy.serviceConfig.EnvironmentFile = config.sops.templates."caddy-env".path;

  services.coredns = {
    enable = true;
    # The catch-all (3rd entry) in the config is needed to prevent DNS amplification attacks
    config = ''
      seed.bitcoin.fish.foo:53 {
        bind 0.0.0.0 ::
        forward . 127.0.0.1:5353
        any
        log
      }

      seed.signet.bitcoin.fish.foo:53 {
        bind 0.0.0.0 ::
        forward . 127.0.0.1:5454
        any
        log
      }

      .:53 {
        bind 0.0.0.0 ::
        template ANY ANY {
          rcode REFUSED
        }
        log
      }
    '';
  };

  services.dnsseedrs.mainnet = {
    enable = lib.mkDefault false;
    chain = "main";
    seedDomain = "seed.bitcoin.fish.foo";
    serverName = "ns.fish.foo";
    soaRname = "will.256k1.dev";
    seedNodes = [
      "54.68.82.186:8333"
      "185.141.60.36:8333"
      "23.175.0.220:8333"
    ];
    threads = lib.mkDefault 6;
    dumpFile = "seeds.txt";
    onionProxy = "127.0.0.1:9050";
    i2pProxy = "127.0.0.1:4447";
    bind = [
      "udp://127.0.0.1:5353"
      "tcp://127.0.0.1:5353"
    ];
    dnssecKeys = "/run/secrets/dnssec-mainnet";
  };

  services.dnsseedrs.signet = {
    enable = lib.mkDefault false;
    chain = "signet";
    seedDomain = "seed.signet.bitcoin.fish.foo";
    serverName = "ns.fish.foo";
    soaRname = "will.256k1.dev";
    threads = lib.mkDefault 6;
    dumpFile = "seeds.txt";
    onionProxy = "127.0.0.1:9050";
    i2pProxy = "127.0.0.1:4447";
    bind = [
      "udp://127.0.0.1:5454"
      "tcp://127.0.0.1:5454"
    ];
    dnssecKeys = "/run/secrets/dnssec-signet";
  };

  # Ensure DNSSEC keys are decrypted before dnsseedrs starts.
  systemd.services.dnsseedrs-mainnet = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
  systemd.services.dnsseedrs-signet = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };

  # Required for remote nixos-rebuild switch via justfile.
  nix.settings.experimental-features = [
    "nix-command"
    "flakes"
  ];
  environment.systemPackages = [
    pkgs.git
    pkgs.ghostty.terminfo
    pkgs.htop
  ];

  networking.firewall.allowedTCPPorts = [
    22
    53
    80
    443
  ];
  networking.firewall.allowedUDPPorts = [ 53 ];

  system.stateVersion = "25.11";
}

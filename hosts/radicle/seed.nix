{ config, ... }:

{
  sops.secrets.radicle-private-key = {
    owner = "radicle";
    group = "radicle";
    mode = "0400";
  };

  services.radicle = {
    enable = true;

    # Generate these once on the server with:
    #   sudo -u radicle RAD_HOME=/var/lib/radicle rad auth --alias radicle.fish.foo
    # Then import the private key into secrets/secrets.yaml as radicle-private-key.
    privateKeyFile = config.sops.secrets.radicle-private-key.path;
    publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPDAHBnAYYRqKFeDBC7VhYa4e6KbIV0VXdW6Bk1QMxZ radicle";

    node = {
      listenAddress = "[::]";
      listenPort = 8776;
      openFirewall = true;
    };

    httpd = {
      enable = true;
      listenAddress = "127.0.0.1";
      listenPort = 8080;
    };

    settings.node = {
      alias = "radicle.fish.foo";
      externalAddresses = [ "radicle.fish.foo:8776" ];
      limits = {
        routingMaxSize = 10000;
        fetchConcurrency = 8;
        maxOpenFiles = 16384;
        fetchPackReceive = "5 GiB";
        rate = {
          inbound = {
            fillRate = 50.0;
            capacity = 8192;
          };
          outbound = {
            fillRate = 50.0;
            capacity = 8192;
          };
        };
        connection = {
          inbound = 512;
          outbound = 128;
        };
      };
      seedingPolicy.default = "block";
      workers = 32;
    };
  };

  systemd.services.radicle-node = {
    after = [ "sops-install-secrets.service" ];
    wants = [ "sops-install-secrets.service" ];
  };
}

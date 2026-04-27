{ ... }:
{
  imports = [
    ../common.nix
    ../radicle.nix
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "dnsseed";
  # Hetzner VMs use eth0; predictable names give ens3 which doesn't match our networkd config.
  networking.usePredictableInterfaceNames = false;
  # Static IP — Hetzner is removing DHCP support.
  networking.useDHCP = false;
  networking.useNetworkd = true;

  systemd.network = {
    enable = true;
    networks."10-eth0" = {
      matchConfig.Name = "eth0";
      address = [
        "135.181.25.255/32"
        "2a01:4f9:c012:aca8::1/64"
        "2a01:4f9:c012:aca8::2/64"
      ];
      routes = [
        # /32 address requires on-link gateway route.
        {
          Gateway = "172.31.1.1";
          GatewayOnLink = true;
        }
        { Gateway = "fe80::1"; }
      ];
    };
  };

  # Tiny Hetzner droplet — cap the mainnet crawler so caddy/tor/i2pd/coredns
  # stay responsive when it saturates cores.
  systemd.services.dnsseedrs-mainnet.serviceConfig = {
    CPUQuota = "150%";
    Nice = 5;
  };
}

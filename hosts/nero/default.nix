{ ... }:
{
  imports = [
    ../common.nix
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "nero";
  networking.useDHCP = true;

  services.dnsseedrs.mainnet.threads = 200;
  services.dnsseedrs.signet = {
    enable = true;
    threads = 10;
  };
}

{ ... }:
{
  imports = [
    ../common.nix
    ../radicle.nix
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
}

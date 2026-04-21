{ ... }:
{
  imports = [
    ../common.nix
    ./disko.nix
    ./hardware-configuration.nix
  ];

  networking.hostName = "nero";
  networking.useDHCP = true;
}

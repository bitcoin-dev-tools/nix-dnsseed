{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.stutman;
  stunserver = lib.getExe' pkgs.stuntman "stunserver";
in
{
  options.stutman.enable = lib.mkEnableOption "STUNTMAN STUN server";

  config = lib.mkIf cfg.enable {
    networking.firewall.allowedTCPPorts = [ 3478 ];
    networking.firewall.allowedUDPPorts = [ 3478 ];

    systemd.services.stuntman-udp = {
      description = "STUNTMAN STUN server (UDP)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        DynamicUser = true;
        ExecStart = "${stunserver} --protocol udp --primaryport 3478";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };

    systemd.services.stuntman-tcp = {
      description = "STUNTMAN STUN server (TCP)";
      after = [ "network.target" ];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        DynamicUser = true;
        ExecStart = "${stunserver} --protocol tcp --primaryport 3478";
        Restart = "on-failure";
        RestartSec = "5s";
      };
    };
  };
}

{ pkgs, ... }:
let
  radicleExplorerConfig = builtins.toJSON {
    nodes = {
      fallbackPublicExplorer = "https://app.radicle.xyz/nodes/$host/$rid$path";
      requiredApiVersion = "~0.18.0";
      defaultHttpdPort = 443;
      defaultLocalHttpdPort = 8080;
      defaultHttpdScheme = "https";
    };
    source.commitsPerPage = 30;
    supportWebsite = "https://radicle.zulipchat.com";
    deploymentId = null;
    preferredSeeds = [
      {
        hostname = "radicle.fish.foo";
        port = 443;
        scheme = "https";
      }
    ];
  };
  radicleExplorer = pkgs.runCommand "radicle-explorer-radicle-fish-foo" { } ''
    cp -R ${pkgs.radicle-explorer} "$out"
    chmod -R u+w "$out"
    substituteInPlace "$out/index.html" \
      --replace-fail '<head>' '<head>
    <script type="text/javascript">
      window.__CONFIG__ = ${radicleExplorerConfig};
    </script>'
  '';
in
{
  services.caddy.virtualHosts."radicle.fish.foo".extraConfig = ''
    handle /api/* {
      reverse_proxy 127.0.0.1:8080
    }

    handle {
      root * ${radicleExplorer}
      try_files {path} /index.html
      file_server
    }
  '';
}

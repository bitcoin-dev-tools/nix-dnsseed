{
  description = "Bitcoin DNS seed deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.11";
    flake-parts.url = "github:hercules-ci/flake-parts";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dnsseedrs = {
      url = "github:willcl-ark/dnsseedrs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    radicle-mirror = {
      url = "path:./radicle-mirror";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    guix-substitutes = {
      url = "path:./guix-substitutes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      perSystem =
        { pkgs, ... }:
        {
          formatter = pkgs.nixfmt-tree;
        };

      flake = {
        nixosConfigurations.dnsseed = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
            inputs.dnsseedrs.nixosModules.default
            {
              nixpkgs.overlays = [ inputs.dnsseedrs.overlays.default ];
            }
            ./hosts/dnsseed
          ];
        };

        nixosConfigurations.nero = inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.disko.nixosModules.disko
            inputs.sops-nix.nixosModules.sops
            inputs.dnsseedrs.nixosModules.default
            inputs.radicle-mirror.nixosModules.default
            inputs.guix-substitutes.nixosModules.default
            {
              nixpkgs.overlays = [ inputs.dnsseedrs.overlays.default ];
            }
            ./hosts/nero
          ];
        };
      };
    };
}

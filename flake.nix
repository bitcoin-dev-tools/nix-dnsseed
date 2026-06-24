{
  description = "Bitcoin DNS seed deployment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    flake-parts.url = "github:hercules-ci/flake-parts";
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dnsseedrs = {
      url = "github:willcl-ark/dnsseedrs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    forgejo-src = {
      url = "github:willcl-ark/forgejo/full-mirror";
      flake = false;
    };
    sops-nix = {
      url = "github:Mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    radicle-mirror = {
      url = "git+file:/home/will/src/nix/modules/radicle-mirror";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    guix-substitutes = {
      url = "git+file:/home/will/src/nix/modules/bitcoin-core-guix-substitutes";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    stuntman = {
      url = "git+file:/home/will/src/nix/modules/stuntman";
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
            inputs.stuntman.nixosModules.default
            {
              nixpkgs.overlays = [
                inputs.dnsseedrs.overlays.default
                (_final: prev: {
                  forgejo = prev.forgejo.overrideAttrs {
                    src = inputs.forgejo-src;
                    vendorHash = "sha256-cb6f7ZX3pG95EEZotGXn6+YUJN59SFNVHFTejFJ6y28=";
                    doCheck = false;
                    postPatch = ''
                      ${prev.forgejo.postPatch}
                      rm -rf vendor
                    '';
                  };
                })
              ];
            }
            ./hosts/nero
          ];
        };
      };
    };
}

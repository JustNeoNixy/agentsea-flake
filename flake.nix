{
  description = "AgentSea — launch AI coding agents on any cloud, wired to The Grid API";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      systems = [ "x86_64-linux" "aarch64-linux" "x86_64-darwin" "aarch64-darwin" ];
      forAllSystems = f:
        nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # version / url / hash of the official prebuilt cli.js (see scripts/update.sh)
      source = builtins.fromJSON (builtins.readFile ./sources.json);
    in
    {
      packages = forAllSystems (pkgs:
        let
          lib = pkgs.lib;

          # The CLI shells out to these (README: bash, curl, ssh, jq).
          runtimeDeps = with pkgs; [ bash curl openssh jq ];

          agentsea = pkgs.stdenvNoCC.mkDerivation {
            pname = "agentsea";
            inherit (source) version;

            # Same artifact the official install.sh downloads.
            src = pkgs.fetchurl { inherit (source) url hash; };

            dontUnpack = true;
            nativeBuildInputs = [ pkgs.makeWrapper ];

            installPhase = ''
              runHook preInstall

              install -Dm644 $src $out/lib/agentsea/cli.js

              # cli.js is a self-contained `--target bun` bundle. The built-in
              # self-updater can't write to the Nix store, so switch it off;
              # updates arrive via sources.json instead.
              makeWrapper ${lib.getExe pkgs.bun} $out/bin/agentsea \
                --add-flags $out/lib/agentsea/cli.js \
                --set-default AGENTSEA_NO_UPDATE_CHECK 1 \
                --set-default AGENTSEA_NO_AUTO_UPDATE 1 \
                --prefix PATH : ${lib.makeBinPath runtimeDeps}

              runHook postInstall
            '';

            meta = {
              description = "Launch any AI coding agent on any cloud, wired to The Grid API";
              homepage = "https://github.com/the-gridai/agentsea";
              license = lib.licenses.asl20;
              mainProgram = "agentsea";
              platforms = systems;
            };
          };
        in
        {
          inherit agentsea;
          default = agentsea;
        });

      overlays.default = final: prev: {
        agentsea = self.packages.${final.stdenv.hostPlatform.system}.agentsea;
      };

      # Adds `agentsea` to environment.systemPackages
      nixosModules.default = { pkgs, ... }: {
        environment.systemPackages = [
          self.packages.${pkgs.stdenv.hostPlatform.system}.agentsea
        ];
      };

      apps = forAllSystems (pkgs: {
        default = {
          type = "app";
          program = "${self.packages.${pkgs.stdenv.hostPlatform.system}.agentsea}/bin/agentsea";
        };
      });

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [ bun bash curl openssh jq ];
        };
      });
    };
}

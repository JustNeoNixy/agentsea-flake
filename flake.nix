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

          # nixpkgs' bun can be a non-baseline x86_64 build, which dies with
          # "Illegal instruction" on CPUs without AVX2 (e.g. Intel Ivy Bridge).
          # Pin bun's official *baseline* build on x86_64-linux instead.
          bun =
            if pkgs.stdenv.hostPlatform.system == "x86_64-linux" then
              pkgs.stdenvNoCC.mkDerivation rec {
                pname = "bun-baseline";
                version = "1.3.9"; # the version upstream builds cli.js with
                src = pkgs.fetchurl {
                  url = "https://github.com/oven-sh/bun/releases/download/bun-v${version}/bun-linux-x64-baseline.zip";
                  hash = "sha256-EE1NA39LNeECFcBQfhd5aR85xXvZHd7v4RyteB4/xLk=";
                };
                nativeBuildInputs = [ pkgs.unzip pkgs.autoPatchelfHook ];
                buildInputs = [ pkgs.openssl ];
                dontConfigure = true;
                dontBuild = true;
                dontStrip = true;
                installPhase = ''
                  runHook preInstall
                  install -Dm755 ./bun $out/bin/bun
                  ln -s $out/bin/bun $out/bin/bunx
                  runHook postInstall
                '';
                meta.mainProgram = "bun";
              }
            else
              pkgs.bun;

          # Claude Code 2.1.113+ ships a native (bun-compiled) binary that needs AVX2 and
          # dies with "Illegal instruction" on older CPUs. 2.1.112 is the last pure-JS
          # build: it only needs node. Opt-in: add this package next to agentsea if
          # your CPU has no AVX2.
          claude-code-js = pkgs.stdenvNoCC.mkDerivation {
            pname = "claude-code-js";
            version = "2.1.112";

            src = pkgs.fetchurl {
              url = "https://registry.npmjs.org/@anthropic-ai/claude-code/-/claude-code-2.1.112.tgz";
              hash = "sha256-hDeZaepToOX9IxqPd96+THyxfdlx9ICdENM/muyl3gk=";
            };
            sourceRoot = "package";
            dontBuild = true;

            launcher = pkgs.writeText "claude-launcher" ''
              #!${pkgs.runtimeShell}
              # AgentSea runs `claude install --force`, which would fetch the native
              # (AVX2-only) build into ~/.local/bin and shadow this one. Make it a no-op.
              if [ "''${1:-}" = install ]; then exit 0; fi
              export DISABLE_AUTOUPDATER=1 USE_BUILTIN_RIPGREP=0
              export PATH="${lib.makeBinPath [ pkgs.ripgrep ]}:$PATH"
              exec ${pkgs.nodejs_22}/bin/node @out@/lib/claude-code/cli.js "$@"
            '';

            installPhase = ''
              runHook preInstall
              mkdir -p $out/lib/claude-code $out/bin
              cp -r . $out/lib/claude-code
              substitute $launcher $out/bin/claude --subst-var out
              chmod +x $out/bin/claude
              runHook postInstall
            '';

            meta = {
              description = "Claude Code 2.1.112 (last pure-JS build, runs on CPUs without AVX2)";
              homepage = "https://github.com/anthropics/claude-code";
              # Proprietary (see LICENSE.md in the package). No meta.license is set so
              # the flake's own nixpkgs instance doesn't refuse to evaluate it as unfree.
              mainProgram = "claude";
            };
          };

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
              makeWrapper ${lib.getExe bun} $out/bin/agentsea \
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
          inherit agentsea bun claude-code-js;
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
          packages = [ self.packages.${pkgs.stdenv.hostPlatform.system}.bun ]
          ++ (with pkgs; [ bash curl openssh jq ]);
        };
      });
    };
}

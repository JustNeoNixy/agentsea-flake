# agentsea-flake

Unofficial Nix flake for [AgentSea](https://github.com/the-gridai/agentsea), the CLI that launches AI coding agents locally or on your own cloud, wired to [The Grid](https://thegrid.ai) API.

It packages the same prebuilt `cli.js` that the official `install.sh` downloads, pinned by hash and run with bun from nixpkgs. A GitHub Actions workflow checks for new releases daily and updates the pin automatically.

> Not affiliated with The Grid or the AgentSea authors.

## Try it without installing

```sh
nix run github:JustNeoNixy/agentsea-flake -- --help
```

## Install

### NixOS (flake-based config)

Add the flake as an input and import its module:

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    agentsea.url = "github:JustNeoNixy/agentsea-flake";
    agentsea.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, agentsea, ... }: {
    nixosConfigurations.<hostname> = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        agentsea.nixosModules.default   # adds `agentsea` to systemPackages
      ];
    };
  };
}
```

Then `sudo nixos-rebuild switch --flake .#<hostname>`.

Prefer to add the package yourself?

```nix
environment.systemPackages = [ agentsea.packages.${pkgs.stdenv.hostPlatform.system}.default ];
```

### Overlay

```nix
nixpkgs.overlays = [ agentsea.overlays.default ];
environment.systemPackages = [ pkgs.agentsea ];
```

### Any system with Nix (no NixOS)

```sh
nix profile install github:JustNeoNixy/agentsea-flake
```

## Usage

```sh
agentsea auth login          # authenticate with The Grid (or set THEGRID_API_KEY)
agentsea claude local        # run an agent on this machine
agentsea claude digitalocean # run an agent on a cloud VM
agentsea agents              # list available agents
agentsea clouds              # list supported clouds
agentsea --help
```

Cloud launches need that provider's token in your environment, for example `DIGITALOCEAN_ACCESS_TOKEN` or `HCLOUD_TOKEN`. See the [AgentSea docs](https://agentsea.thegrid.ai/cli) for details.

## Updating

Automatic: a [daily workflow](.github/workflows/update.yml) runs `scripts/update.sh`, which downloads the latest official `cli.js`, records its version and hash in `sources.json`, verifies that it builds, and commits the change.

To pick up an update on your machine:

```sh
nix flake update agentsea        # in your system flake
sudo nixos-rebuild switch --flake .#<hostname>
```

To update by hand in this repo:

```sh
./scripts/update.sh
```

## Notes

- AgentSea's built-in self-updater is disabled in the wrapper (`AGENTSEA_NO_UPDATE_CHECK` and `AGENTSEA_NO_AUTO_UPDATE`), because the Nix store is read-only. Updates come through this flake instead. You will not see "Update available" prompts.
- On x86_64-linux the flake pins bun's official *baseline* build instead of nixpkgs' bun, so it also runs on older CPUs without AVX2 (a non-baseline bun dies with `Illegal instruction`).
- The wrapper puts `bash`, `curl`, `openssh` and `jq` on `PATH`, since the CLI uses them.
- Upstream publishes the CLI under a rolling `cli-latest` release tag. If a new release lands before the daily workflow runs, builds fail with a hash mismatch until the next update. Running `./scripts/update.sh` fixes it.
- Agent bootstrap scripts are fetched by the CLI at runtime from upstream, so they are not pinned by this flake.

## Development

```sh
nix develop            # shell with bun, bash, curl, openssh, jq
nix build .#agentsea
./result/bin/agentsea version
```

## License

The packaging in this repository is provided as-is. AgentSea itself is licensed under Apache-2.0 by its authors.

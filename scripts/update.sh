#!/usr/bin/env bash
# Re-resolve the official AgentSea CLI release asset and update sources.json.
set -euo pipefail
cd "$(dirname "$0")/.."

url="https://github.com/the-gridai/agentsea/releases/download/cli-latest/cli.js"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

curl -fsSL --proto '=https' "$url" -o "$tmp/cli.js"
[ -s "$tmp/cli.js" ] || { echo "empty download" >&2; exit 1; }

hash="sha256-$(openssl dgst -sha256 -binary "$tmp/cli.js" | base64 | tr -d '\n')"
version=$(grep -aoP 'name:"@agentsea/cli",version:"\K[0-9][^"]*' "$tmp/cli.js" | head -1 || true)
[ -n "$version" ] || { echo "could not detect CLI version" >&2; exit 1; }

jq --arg v "$version" --arg u "$url" --arg h "$hash" \
   '.version=$v | .url=$u | .hash=$h' sources.json > "$tmp/sources.json"

if cmp -s "$tmp/sources.json" sources.json; then
  echo "already up to date ($version)"
  exit 0
fi

cp "$tmp/sources.json" sources.json
git add -N sources.json 2>/dev/null || true   # flakes only see tracked files
nix build .#agentsea --no-link -L
echo "updated to $version"

# aperture-bootstrap — Tailscale Aperture config management
#
# Usage:
#   just build          # compile the Go binary
#   just read            # read current Aperture config
#   just write FILE HASH # push new config with OCC hash
#   just key             # create an ephemeral auth key (needs TS_KEY)
#   just render          # render Dhall config to JSON
#   just fmt             # format Dhall files

set shell := ["bash", "-euo", "pipefail", "-c"]

tailnet := env("TAILNET", "your-tailnet.ts.net")
aperture_url := env("APERTURE_URL", "http://ai/api/config")

# Default: build
default: build

# Compile the bootstrap tool
build:
    go build -o aperture-bootstrap .

# Build with Nix (reproducible)
build-nix:
    nix build .#default

# Create an ephemeral, user-owned auth key (no tags).
# Requires TS_KEY (Tailscale API key, not auth key).
key:
    #!/usr/bin/env bash
    if [ -z "${TS_KEY:-}" ]; then
        echo "TS_KEY is required (Tailscale API key)" >&2
        exit 1
    fi
    curl -s -u "$TS_KEY:" \
        -X POST "https://api.tailscale.com/api/v2/tailnet/{{tailnet}}/keys" \
        -H "Content-Type: application/json" \
        -d '{"capabilities":{"devices":{"create":{"reusable":false,"ephemeral":true,"preauthorized":true,"tags":[]}}},"expirySeconds":300,"description":"aperture-bootstrap"}' \
        | jq -r '.key'

# Read current Aperture config. Prints JSON to stdout, hash to stderr.
# Requires TS_AUTHKEY (ephemeral auth key from `just key`).
read: build
    ./aperture-bootstrap -read -target "{{aperture_url}}"

# Push a new config. Requires the OCC hash from a previous read.
# Usage: just write config/rendered.json abc123hash
write FILE HASH: build
    ./aperture-bootstrap -write "{{FILE}}" -hash "{{HASH}}" -target "{{aperture_url}}"

# Render Dhall config template to JSON
render:
    dhall-to-json --file config/default.dhall > config/rendered.json
    @echo "Wrote config/rendered.json"

# Format all Dhall files
fmt:
    @find config -name '*.dhall' -exec dhall format --output {} {} \;
    @echo "Formatted Dhall files"

# Type-check Dhall config
check:
    @dhall type --file config/default.dhall > /dev/null
    @echo "Dhall type-check passed"

# Full workflow: render config, create key, read current, write new
bootstrap: render
    #!/usr/bin/env bash
    echo "Step 1: Creating ephemeral auth key..."
    export TS_AUTHKEY=$(just key)
    echo "Step 2: Reading current config..."
    HASH=$(./aperture-bootstrap -read -target "{{aperture_url}}" 2>&1 >/dev/null | grep 'hash:' | awk '{print $2}')
    echo "  Current hash: $HASH"
    echo "Step 3: Pushing new config..."
    ./aperture-bootstrap -write config/rendered.json -hash "$HASH" -target "{{aperture_url}}"
    echo "Done."

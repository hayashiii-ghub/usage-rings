#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
swift test
for script in script/*.sh; do bash -n "$script"; done

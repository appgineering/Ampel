#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
swiftc -Onone -swift-version 5 -target arm64-apple-macos14.0 \
  Ampel/Model/SessionState.swift Ampel/Model/AmpelStore.swift Tests/StoreCheck.swift \
  -o "$out/storecheck"
"$out/storecheck"

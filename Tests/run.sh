#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
build() { swiftc -Onone -swift-version 5 -target arm64-apple-macos14.0 "$@"; }

build Ampel/Model/SessionState.swift Ampel/Model/AmpelStore.swift Tests/StoreCheck.swift -o "$out/storecheck"
"$out/storecheck"

build Ampel/Model/UsageProvider.swift Tests/UsageCheck.swift -o "$out/usagecheck"
"$out/usagecheck"

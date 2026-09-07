#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
build() { swiftc -Onone -swift-version 5 -target arm64-apple-macos14.0 "$@"; }

build Ampel/Model/SessionState.swift Ampel/Model/Log.swift Ampel/Model/AmpelStore.swift Tests/StoreCheck.swift -o "$out/storecheck"
"$out/storecheck"

build Ampel/Model/UsageProvider.swift Ampel/Model/Log.swift Ampel/Model/PlanUsage.swift Tests/UsageCheck.swift -o "$out/usagecheck"
"$out/usagecheck"

build Ampel/Model/HookInstaller.swift Ampel/Model/Log.swift Ampel/Model/StatuslineInstaller.swift Ampel/Model/PlanUsage.swift Tests/InstallCheck.swift -o "$out/installcheck"
"$out/installcheck"

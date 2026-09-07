#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)"
swiftc -O -swift-version 5 -parse-as-library -target arm64-apple-macos14.0 Tools/GenerateAppIcon.swift -o "$out/genicon"
"$out/genicon" Ampel/Assets.xcassets/AppIcon.appiconset

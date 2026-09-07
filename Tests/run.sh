#!/bin/bash
# All tests. Noise from the host app's launch is filtered out.
set -euo pipefail
cd "$(dirname "$0")/.."
xcodebuild -project Ampel.xcodeproj -scheme Ampel -destination 'platform=macOS' test 2>&1 \
  | grep -E "Test Case .* (passed|failed)|error:|Executed [0-9]+ test|\*\* TEST" \
  | grep -v "Connection\]"

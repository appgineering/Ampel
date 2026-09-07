#!/bin/bash
# Cut a release: build, sign, notarize, staple, publish, and update the cask.
# Usage: ./Tools/release.sh 0.4.0
#
# Needs: a Developer ID certificate, an App Store Connect API key for
# notarytool, and gh authenticated. The tap is cloned fresh each run so a
# stale local copy cannot publish a wrong hash.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version>}"
IDENTITY="Developer ID Application: Appgineering GbR (PDN9NN6UKR)"
KEY="${ASC_KEY_PATH:-$HOME/OneDrive/AppStoreConnect-Certs/AuthKey_5RAZT4BS6W.p8}"
KEY_ID="${ASC_KEY_ID:-5RAZT4BS6W}"
ISSUER="${ASC_ISSUER_ID:-7b1a8e49-a3df-4058-b96c-47e18cabea35}"
APP=build/Build/Products/Release/Ampel.app
ZIP="dist/Ampel-$VERSION.zip"

[ -z "$(git status --porcelain)" ] || { echo "working tree is dirty"; exit 1; }

echo "==> version"
/usr/bin/sed -i '' "s/CFBundleShortVersionString: \"[^\"]*\"/CFBundleShortVersionString: \\"$VERSION\\"/" project.yml
# yyyymmdd##, counted from the previous value, so it resets each day.
BUILD=$(./Tools/next_build_number.py --write)
echo "    $VERSION build $BUILD"
xcodegen generate >/dev/null

echo "==> build and test"
xcodebuild -project Ampel.xcodeproj -scheme Ampel -configuration Release \
  -derivedDataPath build clean build >/dev/null
./Tests/run.sh >/dev/null || { echo "tests failed"; exit 1; }

echo "==> sign"
codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"

echo "==> notarize"
rm -rf dist && mkdir -p dist
ditto -c -k --keepParent "$APP" "$ZIP"
xcrun notarytool submit "$ZIP" --key "$KEY" --key-id "$KEY_ID" --issuer "$ISSUER" \
  --wait --timeout 30m | tail -2

echo "==> staple"
xcrun stapler staple "$APP"
spctl --assess --type execute "$APP"
# Repackaged after stapling, so the download carries the ticket.
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')

echo "==> publish"
git add project.yml Ampel/Info.plist
git commit -q -m "chore: release $VERSION"
git push -q
# Install instructions live in a file, not in --generate-notes, which would
# ship a changelog with no way to actually install the thing.
NOTES=$(mktemp)
cat Tools/release-notes.md > "$NOTES"
printf '\n## Changes\n\n' >> "$NOTES"
# Tags are created server side by gh, so fetch before describing. The repo has
# two roots after adopting GitHub's initial commit, hence tail -1.
git fetch --tags -q 2>/dev/null || true
PREV=$(git describe --tags --abbrev=0 HEAD 2>/dev/null || git rev-list --max-parents=0 HEAD | tail -1)
git log --pretty='- %s' "$PREV..HEAD" \
  | grep -vE '^- (chore: release|Merge )' >> "$NOTES"
gh release create "v$VERSION" "$ZIP" --repo appgineering/Ampel \
  --title "Ampel $VERSION" --notes-file "$NOTES"
rm -f "$NOTES"

echo "==> cask"
TAP=$(mktemp -d)
git clone -q git@github.com:appgineering/homebrew-tap.git "$TAP"
/usr/bin/python3 - "$TAP/Casks/ampel.rb" "$VERSION" "$SHA" <<'PY'
import re, sys
path, version, sha = sys.argv[1:4]
text = open(path).read()
text = re.sub(r'version "[^"]+"', f'version "{version}"', text)
text = re.sub(r'sha256 "[^"]+"', f'sha256 "{sha}"', text)
open(path, "w").write(text)
PY
git -C "$TAP" commit -qam "Update ampel to $VERSION"
git -C "$TAP" push -q
rm -rf "$TAP"

echo "==> done: $VERSION ($SHA)"

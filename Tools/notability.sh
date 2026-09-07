#!/bin/bash
# How close the repository is to homebrew-cask's notability bar.
#
# Homebrew's own audit refuses a new cask with:
#   GitHub repository not notable enough (<30 forks, <30 watchers and <75 stars)
# Any one of the three is enough. Until then a tap is the only route, which is
# a popularity threshold rather than a technical one, so it is worth watching.
#
# Note "watchers" here is subscribers_count. GitHub's watchers_count is a
# legacy alias for stars and would double count them.
set -uo pipefail
REPO="${1:-appgineering/Ampel}"

read -r STARS FORKS WATCHERS <<<"$(gh api "repos/$REPO" \
  --jq '"\(.stargazers_count) \(.forks_count) \(.subscribers_count)"' 2>/dev/null)" || {
  echo "  could not read $REPO from the GitHub API"; exit 0; }

printf '  stars %s/75, forks %s/30, watchers %s/30\n' "$STARS" "$FORKS" "$WATCHERS"
if [ "$STARS" -ge 75 ] || [ "$FORKS" -ge 30 ] || [ "$WATCHERS" -ge 30 ]; then
  cat <<'MSG'
  Notable enough for homebrew-cask. To drop the tap requirement:
    brew audit --new --cask <tap>/ampel     # confirm it passes
    then open a PR adding Casks/a/ampel.rb to Homebrew/homebrew-cask
MSG
else
  need_s=$((75 - STARS)); need_f=$((30 - FORKS)); need_w=$((30 - WATCHERS))
  printf '  not yet: %s more stars, or %s more forks, or %s more watchers\n' \
    "$need_s" "$need_f" "$need_w"
fi

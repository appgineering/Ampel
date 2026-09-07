A traffic light for your Claude Code sessions, in the macOS menu bar.

Signed with a Developer ID certificate and notarized by Apple, so it opens without a Gatekeeper prompt.

## Install

```sh
brew trust appgineering/tap
brew tap appgineering/tap
brew install --cask ampel
```

`brew trust` comes first. Homebrew refuses to load casks from a tap you have not explicitly trusted, and reports the refusal as `Cannot tap appgineering/tap: invalid syntax in tap!`, which sends you looking for a problem that is not there.

Or download the zip below, unzip it and drag `Ampel.app` to `/Applications`.

## First run

The menu bar icon starts gray. Open it and use the setup guide to install the Claude Code hooks; nothing is tracked until those are in place. Your existing settings and any hooks from other tools are preserved, and a timestamped backup is written first.

Real 5-hour and 7-day plan usage is opt-in under Settings, Usage.

Requires macOS 14 or later, and Claude Code.

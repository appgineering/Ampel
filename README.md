# Ampel

A native macOS menu bar app that shows, at a glance, whether any running Claude Code session needs your attention — like a traffic light.

| Color | State | Meaning |
|---|---|---|
| 🔴 Red | `attention` | Claude is blocked on a decision from you: a permission prompt or a tool asking for input |
| 🟡 Yellow | `working` | Claude is actively processing (tools running, response streaming) |
| 🟢 Green | `idle` | Last turn finished, nothing pending |
| ⚪️ Gray | `off` | No active Claude Code sessions |

Multiple sessions aggregate worst-case: red beats yellow beats green. Clicking the icon opens a menu listing each session (project, state, last activity) plus a usage section: current 5-hour rate-limit block (cost, tokens, reset time) and today's totals.

## How it works

Claude Code hooks (configured in `~/.claude/settings.json`) fire a tiny shell script on lifecycle events. The script drops one JSON file per event into `~/.ampel/events/`. Ampel.app watches that directory, updates per-session state, and renders the aggregate as a colored menu bar icon. No local server, no dependencies in the hook path.

Usage numbers come from [ccusage](https://github.com/ryoppippi/ccusage), which parses the JSONL transcripts under `~/.claude/projects/`. Optional — the app degrades gracefully without it.

## Documents

- `CLAUDE.md` — working agreement for Claude Code building this project
- `docs/SPEC.md` — full technical specification (architecture, hook contract, state machine, UI)
- `docs/MILESTONES.md` — build plan with acceptance criteria, execute in order

## Generating the Xcode project

The project is defined in `project.yml` (XcodeGen). The `.xcodeproj` is generated and gitignored:

```
brew install xcodegen
xcodegen generate
open Ampel.xcodeproj
```

Source stubs under `Ampel/` compile as-is and show a gray circle in the menu bar; the `TODO(M2..M5)` markers map to the milestones.

## Requirements

macOS 14+, Xcode 16+, XcodeGen, Claude Code CLI. Not sandboxed, not for the App Store — a personal utility.

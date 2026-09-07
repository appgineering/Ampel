# Ampel — Technical Specification

## 1. Architecture

```
Claude Code ──hook──▶ ~/.ampel/events/<ts>-<pid>-<rand>.json   (append-only spool)
                                │
Ampel.app ── DispatchSource watch ──▶ drain spool → parse → update session state → delete file
```

Claude Code hooks are shell commands configured in `~/.claude/settings.json`, executed at lifecycle events with a JSON payload on stdin (contains `session_id`, `cwd`, `hook_event_name`, and event-specific fields). Reference: https://code.claude.com/docs/en/hooks-guide

Deliberate decision: **file spool, no localhost server.** It works when the app launches after sessions started, survives app restarts, loses nothing while the app is closed, and the hook path has zero dependencies (no jq, no python, no curl).

## 2. Hook contract

### 2.1 Script `~/.ampel/bin/ampel-hook` (mode 755)

```bash
#!/bin/bash
# Usage: ampel-hook <EventName>   — stdin: Claude Code hook JSON payload
set -u
dir="$HOME/.ampel/events"
mkdir -p "$dir"
payload="$(cat)"
[ -z "$payload" ] && payload='{}'
tmp="$dir/.tmp-$$-$RANDOM"
printf '{"event":"%s","received_at":%s,"payload":%s}' "$1" "$(date +%s)" "$payload" > "$tmp"
mv "$tmp" "$dir/$(date +%s)-$$-$RANDOM.json"
exit 0
```

Write-then-rename prevents the watcher from reading half-written files. Always exits 0.

### 2.2 Hooks block for `~/.claude/settings.json` (merge, never overwrite; backup first)

```json
{
  "hooks": {
    "SessionStart":     [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook SessionStart" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook UserPromptSubmit" }] }],
    "PreToolUse":       [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook PreToolUse" }] }],
    "PostToolUse":      [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook PostToolUse" }] }],
    "Notification":     [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook Notification" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook Stop" }] }],
    "SubagentStop":     [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook SubagentStop" }] }],
    "SessionEnd":       [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook SessionEnd" }] }]
  }
}
```

### 2.3 Envelope format

```json
{ "event": "Stop", "received_at": 1725690000, "payload": { "session_id": "…", "cwd": "/Users/kevin/dev/foo", "hook_event_name": "Stop", "…": "…" } }
```

## 3. State model

```swift
enum SessionActivity { case idle, working, attention }

struct Session {
  let id: String          // payload.session_id
  var cwd: String
  var activity: SessionActivity
  var lastActivity: Date
  var lastMessage: String? // Notification payload "message", if present
}
```

Transition table, keyed by `session_id`:

| Event | Effect |
|---|---|
| `SessionStart` | upsert session, `idle` |
| `UserPromptSubmit` | `working` |
| `PreToolUse` / `PostToolUse` | `working` |
| `Notification` | `attention`, store `message` |
| `Stop` / `SubagentStop` | `idle` |
| `SessionEnd` | remove session |

Every event updates `lastActivity` and `cwd`. Display name = `URL(fileURLWithPath: cwd).lastPathComponent`.

Aggregate for the icon: `attention > working > idle`; `off` when no sessions.

Housekeeping: 60s timer removes sessions with `lastActivity` older than 6 hours (killed terminals never send `SessionEnd`).

## 4. Event watcher

`DispatchSource.makeFileSystemObjectSource` on an `O_EVTONLY` file descriptor of `~/.ampel/events`, event mask `.write`. On every fire AND once on app launch: drain the spool — list `*.json` (skip `.tmp-*`), sort by filename ascending, decode, apply, delete. Malformed files: delete and log, never crash. Draining on launch replays everything that happened while the app was closed.

## 5. Menu bar icon

18×18 pt `NSImage`, `isTemplate = false`, filled circle:

- `off` → systemGray, `idle` → systemGreen, `working` → systemYellow, `attention` → systemRed.
- `attention` only: pulse opacity 1.0 ↔ 0.5, 1s ease-in-out, via timer swapping pre-rendered frames. Zero timer activity in all other states.

## 6. Menu UI

`MenuBarExtra` with `.menuBarExtraStyle(.window)`. Content top to bottom:

1. Header: aggregate summary ("1 session needs attention" / "2 sessions working" / "All quiet").
2. Session rows: colored dot, project name, state label, relative time ("2m ago"). `attention` sessions sorted first; show `lastMessage` as secondary line when present.
3. Divider, usage section (§7).
4. Footer: "Launch at Login" toggle (`SMAppService.mainApp`), "Install hooks…" (only when setup incomplete, §8), "Quit".

macOS notification (`UNUserNotificationCenter`) when a session transitions INTO `attention`: title = project name, body = payload `message` or "Claude needs your attention". Debounce: max one per session per 30s. No notifications for any other transition.

## 7. Usage section

`UsageProvider` refreshes when the menu opens, caches 60s, runs off the main thread via `Process` with 10s timeout:

- `ccusage blocks --json` → active block → cost, tokens, block end time → "Current block: $X.XX · N tokens · resets HH:MM"
- `ccusage daily --json` → today → "Today: $Y.YY"

Binary resolution order: `ccusage` on PATH (via `/usr/bin/env`), then `bunx ccusage`, then `npx -y ccusage`. On any failure: render "Usage unavailable — brew install ccusage" and log; never block or crash the menu.

## 8. First-run setup

On launch, check: hook script exists and is executable; all eight hook entries present in `~/.claude/settings.json`. If incomplete, badge the menu with "Install hooks…" which: backs up settings.json (`settings.json.bak-<epoch>`), writes the script, merges the hooks block (preserving unrelated hooks and any existing hooks on the same events by appending, not replacing), reports success in the menu.

## 9. Project layout

```
Ampel/
  AmpelApp.swift            // @main, MenuBarExtra
  Model/
    SessionState.swift
    AmpelStore.swift        // @Observable; sessions, aggregate, apply(event:)
    EventWatcher.swift
    UsageProvider.swift
    HookInstaller.swift
  UI/
    MenuContent.swift
    StatusIcon.swift
```

## 10. Known caveats

- The `Notification` hook fires on permission prompts and after ~60s idle waiting for input. It is known to be unreliable in some IDE-extension environments; the terminal CLI is the reference environment.
- ccusage numbers are estimates derived from local transcripts, not an official API.

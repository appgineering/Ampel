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
envelope="$(printf '{"event":"%s","received_at":%s,"payload":%s}' "$1" "$(date +%s)" "$payload")"
tmp="$dir/.tmp-$$-$RANDOM"
printf '%s' "$envelope" > "$tmp"
mv "$tmp" "$dir/$(date +%s)-$$-$RANDOM.json"
[ -e "$HOME/.ampel/debug" ] && printf '%s\n' "$envelope" >> "$HOME/.ampel/hook.log"
exit 0
```

Write-then-rename prevents the watcher from reading half-written files. Always exits 0.

The app deletes each spool file once applied, so a sequence of events cannot be reconstructed afterwards. Creating `~/.ampel/debug` makes the hook also append every envelope to `~/.ampel/hook.log`, which is the only way to tell a lost event apart from a mishandled one. Off by default: the file does not exist.

### 2.2 Hooks block for `~/.claude/settings.json` (merge, never overwrite; backup first)

```json
{
  "hooks": {
    "SessionStart":     [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook SessionStart" }] }],
    "UserPromptSubmit": [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook UserPromptSubmit" }] }],
    "PreToolUse":       [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook PreToolUse" }] }],
    "PostToolUse":      [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook PostToolUse" }] }],
    "Notification":     [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook Notification" }] }],
    "Stop":             [{ "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook Stop" }] }],
    "SubagentStop":     [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook SubagentStop" }] }],
    "SessionEnd":       [{ "matcher": "*", "hooks": [{ "type": "command", "command": "~/.ampel/bin/ampel-hook SessionEnd" }] }]
  }
}
```

`UserPromptSubmit` and `Stop` do not support a matcher (one is silently ignored there); every other event we use does, and `"*"` means match all. Each event's value is an array of matcher groups, so installing means appending a group, never replacing the array.

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
| `Notification` | `attention` when `notification_type` warrants it (below), store `message` |
| `Stop` / `SubagentStop` | `idle` |
| `SessionEnd` | remove session |

The `Notification` payload carries both `message` (human-readable, e.g. "Claude is waiting for your input") and `notification_type` (`permission_prompt`, `idle_prompt`, `agent_needs_input`, …).

Only notifications that represent a decision waiting on the user turn a session red: `permission_prompt`, `agent_needs_input`, and the `elicitation_*` dialogs. `idle_prompt` does not, because Claude Code fires it whenever a session sits at an empty prompt, which is most of the time a session is open and would pin the icon red permanently. A `Notification` with an unrecognised or absent `notification_type` is treated as needing attention, so a new blocking notification type shows up rather than being silently swallowed. `lastMessage` is cleared whenever a session leaves `attention`, so a green row never shows a stale "waiting for your input".

Every event updates `lastActivity` and `cwd`. Display name = `URL(fileURLWithPath: cwd).lastPathComponent`.

Aggregate for the icon: `attention > working > idle`; `off` when no sessions.

Housekeeping: 60s timer removes sessions with `lastActivity` older than 6 hours (killed terminals never send `SessionEnd`).

## 4. Event watcher

`DispatchSource.makeFileSystemObjectSource` on an `O_EVTONLY` file descriptor of `~/.ampel/events`, event mask `.write`. On every fire AND once on app launch: drain the spool — list `*.json` (skip `.tmp-*`), sort by modification time ascending with the filename as tiebreak, decode, apply, delete.

Ordering must not use the filename alone: the hook names files with a whole-second `date +%s`, and several events landing in the same second is routine (observed within a single three-minute session). Two events out of order can leave the icon stuck on the wrong colour until the next event. APFS mtimes are nanosecond-resolution and `mv` preserves the tmp file's write time, so mtime is the correct ordering key and the hook script needs no sub-second clock (macOS ships bash 3.2, which has neither `EPOCHREALTIME` nor a `%N` in BSD `date`). Malformed files: delete and log, never crash. Draining on launch replays everything that happened while the app was closed.

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

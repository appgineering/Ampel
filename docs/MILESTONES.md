# Ampel — Milestones

Execute in order. Do not start a milestone until the previous one's acceptance criteria pass. Spec references are to `docs/SPEC.md`.

## M1 — Hook plumbing

Create `~/.ampel/bin/ampel-hook` (SPEC §2.1) and merge the hooks block into `~/.claude/settings.json` (SPEC §2.2) with a timestamped backup.

**Accept:** Start a Claude Code session in a terminal, send a prompt, let it finish. `ls ~/.ampel/events` shows files for SessionStart, UserPromptSubmit, Pre/PostToolUse, Stop. Each file is valid JSON per SPEC §2.3 with `session_id` and `cwd` in the payload. `~/.claude/settings.json` still contains all pre-existing settings.

## M2 — App skeleton and event engine

The project scaffold already exists: `project.yml` (XcodeGen) plus compiling stubs under `Ampel/` with `TODO(M2)` markers. Run `xcodegen generate`, confirm the app builds and shows a gray circle. Then implement the TODOs: `AmpelStore.apply(_:)` with the transition table (SPEC §3), `sweepStale` on a 60s timer, `EventWatcher` with launch-drain (SPEC §4), and wire the watcher in `AmpelApp`. `StatusIcon` is already implemented (static states only).

**Accept:** With the app running, a normal Claude Code turn flips the icon gray→green→yellow→green in real time. A permission prompt flips it red; approving returns to yellow. Quit the app mid-turn, relaunch after the turn ends: icon shows the correct final state (spool replay works). Malformed file dropped into the spool is deleted without a crash.

## M3 — Menu UI and notifications

Implement `MenuContent` per SPEC §6: header, session rows, footer with Launch at Login and Quit. Add the `attention` transition notification with 30s debounce.

**Accept:** Menu shows live sessions with correct project names, states, and relative times; two parallel sessions in different projects appear as two rows and aggregate worst-case. Red transition produces exactly one system notification with the project name. Launch-at-login toggle state survives app restart.

## M4 — Usage section

Implement `UsageProvider` per SPEC §7.

**Accept:** Menu numbers match `ccusage blocks --json` / `ccusage daily --json` run manually in a terminal. Renaming the ccusage binary away (simulated missing install) yields the fallback line, menu stays instant, no crash.

## M5 — Polish and install

Pulse animation for `attention` (SPEC §5). First-run "Install hooks…" flow (SPEC §8). Release build, ad-hoc codesign (`codesign --force --deep -s -`), copy to `/Applications`.

**Accept:** Fresh-machine test from CLAUDE.md's definition of done passes end to end, starting from a deleted `~/.ampel`. CPU usage of the idle app (green/gray state) is ~0% in Activity Monitor. Ghost-session TTL: kill a terminal mid-turn, confirm the session row disappears after the sweep (temporarily lower the TTL to test).

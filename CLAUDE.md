# CLAUDE.md — Ampel

macOS menu bar app showing Claude Code session status as a traffic light. Read `docs/SPEC.md` for the full design and `docs/MILESTONES.md` for the build order before writing any code.

## Workflow rules

1. Execute `docs/MILESTONES.md` strictly in order. Do not start a milestone until the previous one's acceptance criteria pass. Verify them yourself where possible (build, run scripts, inspect files) and tell the user exactly what to check manually.
2. When the spec and reality disagree (API renamed, hook payload differs), follow reality, then update `docs/SPEC.md` in the same commit and note the deviation.
3. Never modify `~/.claude/settings.json` destructively. Always merge and always write a timestamped backup first (`settings.json.bak-<epoch>`).
4. Hook scripts must always `exit 0` and must never write to stdout/stderr in the success path. Ampel must be invisible to Claude Code's own hook semantics. The statusLine wrapper is the one exception: it is opt-in, and it prints only what the statusline it replaced would have printed.
5. Commit per milestone, conventional commits (`feat:`, `fix:`, `chore:`), imperative subject.

## Tech constraints (non-negotiable)

- Swift 5.10+, SwiftUI, deployment target macOS 14.0.
- The menu bar item is an `NSStatusItem` owned by `StatusItemController`, not `MenuBarExtra`. `MenuBarExtra` exposes no right-click and re-renders its whole scene on every label change, which cost 23% CPU for the attention pulse. All content is still SwiftUI, hosted in an `NSPopover` and two plain `NSWindow`s.
- The Xcode project is generated from `project.yml` via XcodeGen. Never hand-edit the `.pbxproj`; change `project.yml` and run `xcodegen generate`. New source files under `Ampel/` are picked up automatically on regeneration.
- App bundle `Ampel.app`, bundle id `com.appgineering.ampel`.
- `LSUIElement = true` — no Dock icon, no main window.
- Zero third-party Swift dependencies. No SPM packages.
- App Sandbox OFF (reads `~/.ampel`, spawns `ccusage`).
- Menu bar icon: programmatically rendered `NSImage` with `isTemplate = false` (colored circles must not be tinted by the system).
- All file watching via `DispatchSource.makeFileSystemObjectSource`; all subprocess work via `Process` off the main thread with timeouts.
- State model: `@Observable` classes, no Combine, no NotificationCenter for internal state.

## Code style

- Small files, one type per file, folders as in the spec's project layout.
- No force unwraps outside tests. Decode hook payloads defensively: unknown events are ignored and logged, malformed files are deleted and logged, never crash on spool content.
- `os.Logger` with subsystem `com.appgineering.ampel`, one category per component (`watcher`, `store`, `usage`, `ui`).

## Definition of done (whole project)

Fresh-machine test passes: delete `~/.ampel`, launch app, run first-run hook install from the menu, start a Claude Code session in a terminal, observe gray→green→yellow→green on a normal turn, red on a permission prompt, one macOS notification on the red transition, plausible usage numbers in the menu.

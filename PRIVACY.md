# Privacy

Ampel collects nothing, sends nothing, and has no analytics, telemetry, crash
reporting service or account. It makes no network requests of its own. There is
no policy to agree to because there is no data collection to describe.

What follows is what the app touches on your own machine, so you can judge it
rather than take the paragraph above on trust.

## What Ampel reads

- `~/.ampel/events/` — one file per Claude Code lifecycle event, written by the
  hook script. Ampel reads `session_id`, `cwd`, and a notification `message`,
  then deletes the file. The rest of each payload is ignored.
- `~/.claude/settings.json` — to check whether its hooks are installed, and to
  merge them in when you ask. A timestamped backup is written first.
- `~/.ampel/usage.json` — the statusLine payload, only if you turn on real plan
  usage. It contains your rate limit percentages.
- `~/Library/Logs/DiagnosticReports/Ampel-*.ips` — only to tell you a crash
  report exists and to include it when you press Copy diagnostics.

## What Ampel writes

- `~/.ampel/` — the hook script, the event spool, a usage cache, and
  `ampel.log`, which records session ids, project directory names and state
  changes. It rotates once at 512KB.
- `~/.claude/settings.json` — the hooks block, and the `statusLine` entry if you
  opt into plan usage. Existing settings and other tools' hooks are preserved.
- Your clipboard, when you press Copy diagnostics.

## The one thing worth knowing

Creating `~/.ampel/debug` makes the hook append **every event payload verbatim**
to `~/.ampel/hook.log`. Those payloads include the text of your prompts. It is
off by default, it is only for diagnosing a problem, and you should delete the
file and the log when you are done. Nothing sends it anywhere; it simply sits on
your disk until you remove it.

## Other software

`ccusage`, if installed, is run as a separate process to estimate cost from the
transcripts already on your machine. It is not part of Ampel. When `ccusage` is
not installed, Ampel may fall back to `bunx` or `npx`, which download it from
the npm registry; if you would rather nothing reached the network, install
`ccusage` yourself or leave the usage section hidden.

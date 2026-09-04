---
name: quickstart
description: Quick orientation and environment setup for starting work in the BlueBubbles repo — what to read first, how to actually run and live-verify a change (especially the deprecated web client), and the git/lint workflow. Use at the start of any new BlueBubbles task, especially before touching code or trying to test a change live.
---

# BlueBubbles Quickstart

Fast-path orientation for a new chat/ask in this repo. This is the *operational*
companion to the `CLAUDE.md` files (already loaded as context) — it exists for the
parts that cost real time to rediscover from scratch: environment quirks, exact
commands, and where the current-state docs live.

## 1. Orient before touching code

- Root `CLAUDE.md` — architecture map, key conventions. Note it points to
  per-directory `CLAUDE.md` files (`lib/CLAUDE.md`, `android/CLAUDE.md`, etc.) —
  read the one for whatever area you're touching.
- `.claude/CLAUDE.md` — links to `.claude/rules/*.md` (frontend/api/database/services/git
  conventions) and `docs/*.md` (architecture, decisions, common tasks, message flow
  traces). Load the relevant rule file(s) *before* writing code, not after.
- `.claude/WEB_CLIENT_DEBUGGING.md` — if the task touches the web client
  (`lib/database/html/`, `lib/models/html/`, anything gated by `kIsWeb`), or asks to
  verify something live in a browser, **read this first**. It's the running log of
  what's fixed, what's root-caused but not fixed, and known gotchas for this
  specific deprecated-but-actively-debugged platform. Update it when you fix or find
  something new there — don't let it go stale.

## 2. Lint/build tooling isn't on PATH by default

`dart`/`flutter` aren't found by a bare `dart analyze` in this environment. Export
once per session:

```bash
export PATH="$PATH:/home/sammorris/dev/flutter/bin:/home/sammorris/dev/flutter/bin/cache/dart-sdk/bin"
```

Then `dart analyze <files>` works normally. Run it after every edit — this repo has
no automated test suite, so lint-clean is the fast correctness signal before live
verification.

## 3. Running the app to verify a change live

### Deprecated web client (`flutter run -d web-server`)

Fastest way to see a change without a full native build, but has sharp edges — see
`.claude/WEB_CLIENT_DEBUGGING.md` → "How to run it" for the full writeup. Short version:

- Serve with a FIFO on stdin so hot restart works after the process is detached:
  ```bash
  mkfifo /tmp/fltr.fifo
  sleep infinity > /tmp/fltr.fifo &
  flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8090 \
      --no-web-experimental-hot-reload < /tmp/fltr.fifo > /tmp/flutter_run.log 2>&1 &
  ```
- After editing Dart: `echo R > /tmp/fltr.fifo` (hot restart). The web-server device
  does **not** rebuild on a bare browser reload — only on this.
- The app is served at `http://<host>:8090/web`, **not** `/` — hitting the bare host
  returns a 404 that looks like a dead server but isn't.
- To drive it live, use the Claude-in-Chrome tools. Load the core set in one call
  before first use (batch every tool the task needs — each separate `ToolSearch`
  call costs a full round trip):
  ```
  ToolSearch("select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__tabs_close_mcp,mcp__claude-in-chrome__read_console_messages,mcp__claude-in-chrome__browser_batch")
  ```
  Add `read_network_requests` / `find` / `javascript_tool` / `file_upload` only if
  the task specifically needs them.
- `read_console_messages` **always** needs a tight `pattern` — the console is
  flooded with unrelated startup/sync logs.
- After a hot restart, navigate/reload the tab and wait ~8-10s before checking
  anything — the app takes a moment to reinitialize services after restart.
- Prefer `browser_batch` over sequential single calls when you can predict two or
  more steps ahead (navigate → wait → screenshot, click → type → screenshot, etc.).

### Other platforms

No project-specific launch procedure is documented yet for Android/iOS/macOS/Windows/Linux
native builds — the generic `run` skill's fallback patterns apply. If you work one
out, add it here so the next session doesn't have to rediscover it.

## 4. Git workflow

- Branch off `master`; PRs target `master`. See `.claude/rules/git.md` for commit
  message format (`<type>: <lowercase message>`, no scope parens, no trailing period)
  before committing.
- If you're on a fork-only branch (check the top of the relevant tracking doc, e.g.
  `.claude/WEB_CLIENT_DEBUGGING.md` → "Git setup for this work"): some work in this
  repo is fork-only by explicit user instruction — `origin` is the fork (push here),
  `upstream` is read-only. Don't open PRs against `upstream` without checking first.
- No CI — `dart analyze` (§2) plus live verification (§3) is the whole safety net.
  Don't skip live verification for anything UI-visible just because lint is clean;
  several bugs in this repo's history were only found by actually looking at the
  rendered result, not by reading the diff.

## Common trap: web has its own model files, not always where you'd expect

Editing `lib/database/io/*.dart` alone for something that also needs to work on web
can silently miss the real target. Check `lib/database/models.dart`'s conditional
exports first:

```bash
grep -n "if (dart.library.html)" lib/database/models.dart
```

Most `io/` entities have a mirror in `lib/database/html/`, but at least one
(`ContactV2`) instead mirrors under `lib/models/html/` — a different top-level
directory, easy to miss, and not listed in `lib/database/html/CLAUDE.md`'s file
inventory. When a shared widget references a field on a conditionally-exported type,
that field has to exist on **both** concrete implementations or the platform you
didn't check will fail to compile.

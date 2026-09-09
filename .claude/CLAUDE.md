# Claude Workflow — BlueBubbles

## Getting Started
Run the `quickstart` skill (`.claude/skills/quickstart/SKILL.md`) at the start of a
new task — it covers PATH setup for `dart`/`flutter`, how to run and live-verify a
change (including the web-server hot-restart workflow and Claude-in-Chrome tool
setup), and the git/fork workflow, without re-deriving them each session.

## Rules
Detailed coding standards live in `.claude/rules/`:
- `frontend.md` — widget patterns, state, theming, naming
- `api.md` — HTTP calls, interface→action pattern, error handling
- `database.md` — ObjectBox entities, queries, transactions, serialization
- `services.md` — service access, event dispatch, method channels, navigation
- `git.md` — commit message format

## In-Progress Work
- `.claude/WEB_CLIENT_DEBUGGING.md` — status of an active effort to get the deprecated
  web client (`flutter run -d web-server`) working for live bug debugging: what's
  fixed, what's root-caused but not fixed, and the git remote setup (fork-only, no
  upstream PRs). Check this before starting web-related work.

## Architecture & Design Decisions
- `docs/ARCHITECTURE.md` — how the system's major subsystems work and interact
- `docs/DECISIONS.md` — why key design choices were made (isolate pattern, GetIt vs GetX, ChatState, etc.)
- `docs/COMMON_TASKS.md` — step-by-step recipes for frequent development tasks
- `docs/MESSAGE_RECEIVE_FLOW.md` — end-to-end trace: socket → queue → DB → state → UI
- `docs/MESSAGE_SEND_FLOW.md` — end-to-end trace: send button → tempGuid → HTTP + socket race → real GUID swap
- `docs/MODELS.md` — reference for the DB entity / DTO model landscape (`lib/database/`, `lib/models/`)
- `docs/THEMING_AND_COMPONENTS.md` — reusable `BBScaffold`/`BBAppBar`/`BBChip`/dialog wrappers, skin vs. theme mechanics, color access patterns

## Before Making Changes
- Check for `CLAUDE.md` in the target directory
- Read root `CLAUDE.md` for architecture orientation
- For non-trivial tasks, read `docs/ARCHITECTURE.md` and the relevant section of `docs/DECISIONS.md`
- Load the relevant rule file(s) from `.claude/rules/` before writing code

## Code Generation
After editing `@Entity` classes in `lib/database/io/`:
→ `dart run build_runner build`
→ Never edit `lib/generated/objectbox.g.dart` directly

## Lint / Style
- `bash scripts/dart-fix-common-issues.sh` — runs `dart fix --apply` for common issues
- Line length: 120 chars

## Testing
No automated test suite. Verify changes by running the target platform.

## Branches
Branch off `master`; PRs target `master`. No CI/CD.

# Web Client Debugging — Status

Working notes for an in-progress effort to get `flutter run -d web-server` fully
functional so bugs can be debugged live in a browser. Web support is otherwise
**deprecated** (see root `CLAUDE.md`) — this work is scoped to unblocking live
debugging, not building out the web platform. Update this file as the work
continues; delete it once the effort is closed out.

## How to run it

```
flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8090 --no-web-experimental-hot-reload
```

Two gotchas that cost time before:

- **The app is served at `/web`, not `/`.** `flutter run` prints
  `lib/main.dart is being served at http://0.0.0.0:8090/web`. Hitting `http://<host>:8090/`
  returns a bare 404 (which Chrome renders as its own error page), so it looks like the
  dev server is broken when it is fine. Always open `http://<host>:8090/web`.
- **The web-server device does not rebuild on page reload.** A browser refresh re-serves
  the modules compiled at `flutter run` time, so edits made after launch are invisible and
  you end up debugging a stale build. Trigger a hot restart (`R` on the `flutter run`
  stdin) or relaunch the process after editing Dart. To make `R` reachable when the
  process is launched detached, give it a FIFO for stdin and hold the FIFO open:

  ```
  mkfifo /tmp/fltr.fifo
  sleep infinity > /tmp/fltr.fifo &          # keeps stdin from hitting EOF
  flutter run -d web-server --web-hostname 0.0.0.0 --web-port 8090 \
      --no-web-experimental-hot-reload < /tmp/fltr.fifo > /tmp/flutter_run.log 2>&1 &
  echo R > /tmp/fltr.fifo                    # hot restart
  ```

`web/index.html` has a debug-only JS error forwarder (`<script id="bb-debug-error-forwarder">`)
gated behind a `data-bb-debug` attribute set in `lib/main.dart`'s `kIsWeb && kDebugMode` block.
It POSTs uncaught errors and `[ERROR]`/`[WARN]`-tagged console lines to
`http://<hostname>:8091/log` so they don't have to be copy-pasted from DevTools by hand.
There is no committed collector script for that endpoint — write a small local HTTP
server if you want to use it again (a `ThreadingHTTPServer` that just logs the POST body
is enough); it isn't part of the repo since it's a personal debugging aid, not app code.

## Git setup for this work

This repo only has **read** access to `BlueBubblesApp/bluebubbles-app` upstream.
All work happens on a fork, `sammorris81/bluebubbles-app`. Remotes are set up the
standard fork way:

- `origin` → `sammorris81/bluebubbles-app` (push here — this is the default)
- `upstream` → `BlueBubblesApp/bluebubbles-app` (fetch-only, to stay in sync with `master`)

**Do not open PRs against upstream for this work** — an earlier PR
(`BlueBubblesApp/bluebubbles-app#3257`) was opened and then explicitly closed by the
user, who wants this kept on the fork only. Just commit and `git push` (goes to
`origin`/the fork automatically).

Branch: `claude/web-client-support-fixes`, already pushed to `origin` with one
commit (`fix: get web client building, syncing messages, and loading contacts`)
covering the "build/compile + message loading + contacts routing" fixes below.
Add new fixes as new commits on top rather than amending.

## The three original bugs

### 1. Message sorting — fixed (within a conversation)
`lib/database/html/message.dart` gained a `Message.sort(a, b, {descending})` static
comparator mirroring the io/ one (handles the Mac dateCreated-vs-dateDelivered
ordering quirk). This is per-conversation message order, not the chat list.

### 2. Chat list sort order — fixed and verified live
Reported symptom: the conversation list is not newest-first; order looks arbitrary /
stuck at load order.

Root cause found: `Chat.getChatsAsync()` in `lib/database/html/chat.dart` (the web
path for loading the initial chat list, since there's no local ObjectBox DB to query)
called `HttpSvc.chat.query(withQuery: const ["participants"], ...)` — **without**
`"lastmessage"`. `Chat.fromMap()` already knows how to hydrate `dbLatestMessage` /
`dbOnlyLatestMessageDate` from `json['lastMessage']` (see line ~163), but that key was
never present in the response, so every chat's latest-message date stayed `null` →
`ChatsService._sortCompare` / `Chat.sort()` both fall back to epoch-0 for all of them
→ initial insertion order is whatever the server returned (participant order), not
newest-first. Chats only jumped to the correct place once opened, since that's the
only other path that calls `ChatsSvc.updateChatLatestMessage()` (which does correctly
trigger `_repositionChat`).

Fix: added `"lastmessage"` to the `withQuery` list in
`Chat.getChatsAsync()` (`lib/database/html/chat.dart`, the `HttpSvc.chat.query(...)`
call inside it). `ChatsService`'s own sort
comparator (`_sortCompare` in `lib/services/ui/chat/chats_service.dart`) and the
binary-search insertion logic (`_findInsertionIndex`/`_insertChatSorted`) were read in
full and look structurally correct — pin-index ordering, then pinned-without-index,
then most-recent-message descending, all handled consistently. No changes were needed
there.

**Verified** in a live browser (Claude in Chrome driving Chrome on the Mac against
`http://10.7.12.13:8090/web`): with the fix compiled in, every tile renders a message
preview and timestamp and the list is correctly newest-first on initial load, all the
way down the list — no need to open a chat first.

An earlier round of testing reported the list as "better but still only partially
sorted". That was a false negative: the `flutter run` process had been started *before*
`chat.dart` was edited, and the web-server device does not rebuild on page reload, so
the browser was still running a pre-fix build. See the rebuild gotcha under
"How to run it" — check process start time against file mtime before trusting a
negative result.

### 3. Photo downloading — not started
Not yet investigated this session at all.

### Contacts not loading/displaying on web — fixed and verified live
(Reported by the user during this same debugging pass; separate from the three
original bugs but discovered along the way.)

Root causes (all confirmed empirically):
- On web, `Database.init()` returns early, so `Database.store` and every `Box` are
  uninitialized `late final`. The old Step 2 of contact sync threw
  `LateInitializationError: Field 'store' has not been initialized` before matching a
  single contact — confirmed in the browser console. The 474-contact fetch itself was
  fine; only the matching half was broken.
- Ordering bug: `ContactServiceV2.init()` fires its first sync (from `StartupTasks`)
  before the chat list has loaded any handles, so that first pass always matches zero.
  Confirmed by timestamps in one run: contact sync completed at `15:10:52.254`, chats
  finished loading at `15:10:52.558`.
- `/chat/query` returns participants carrying only `originalROWID` — no `ROWID` and no
  `id` (verified by calling the endpoint directly from the page). `Handle.fromMap` left
  `id` null for every web handle as a result, so `HandleService.getOrCreateHandleState`
  returned an uncached, ephemeral `HandleState` for every participant, and
  `affectedHandleIds` was always empty. This is why an intermediate test run logged
  `Matched 115/474 contacts to in-memory handles` but `notifying UI of 0 affected
  handles` — matching worked, but nothing could reach the UI. Avatars picked up contact
  initials in that state (that widget reads the mutated `Handle` directly) while titles
  still showed phone numbers (those go through `ChatState.title`, which only updates via
  the `ever(hs.displayName, ...)` worker on a *registered* `HandleState`).

Fix (four files, all live-verified against `http://10.7.12.13:8090/web`):
- `lib/services/backend/actions/contact_v2_actions.dart` — extracted shared
  side-effect-free helpers (`_buildHandleLookupMaps`, `_normalizedAddressesFor`,
  `_matchHandles`) out of the old Step 2, then added `_matchContactsToWebHandles(...)`,
  a web-only replacement that matches server-fetched contacts against the in-memory
  handles from `ChatsSvc.webCachedHandles` plus every loaded chat's `handles`, and
  attaches results to `handle.contactsV2`. Step 2 now branches:
  `if (kIsWeb) { _matchContactsToWebHandles(...) } else { Database.runInTransaction(...) }`.
  Also skips `_saveContactAvatar` on web and requests `withAvatars: !kIsWeb` (avatar
  downloading is a separate, not-yet-investigated item — see below).
- `lib/services/ui/contact_service_v2.dart` — added `_notifyHandlesUpdatedWeb()`, a web
  path for `notifyHandlesUpdated` that pushes the in-memory handles through
  `HandleSvc.updateHandleStates`.
- `lib/services/ui/chat/chats_service.dart` — at the end of `_initInternal()`, on web,
  re-runs `ContactsSvcV2.syncContactsToHandles(wait: false)` after the chat list (and
  its handles) have loaded, fixing the ordering bug above.
- `lib/database/html/handle.dart` — `Handle.fromMap` now falls back to `originalROWID`
  for `id`: `json["ROWID"] ?? json["id"] ?? json["originalROWID"]`, fixing the missing-id
  bug above so handles get real, cacheable ids and `HandleState`s are no longer
  ephemeral.

**Verified live**: after the fix, console shows
`Matched 115/474 contacts to in-memory handles` →
`notifying UI of 92 affected handles` → `Refreshed 92 web handle states after contact
sync`, and chat tiles render real contact names (e.g. "Vickie Woodard (Weber)", "Jake
Hegge", "Miranda Panzer") instead of raw phone numbers. Tiles for numbers with no
matching contact correctly continue to show the raw number — that's expected, not a
bug. Note the very first sync (fired by `ContactServiceV2.init()` before chats load)
still logs 0 affected handles, as expected — it's the *second* sync, triggered from
`chats_service.dart` after handles exist, that succeeds.

### Link-preview CORS image errors — cosmetic, no fix needed
Browser console showed CORS-blocked image loads for `share.1password.com` Open Graph
preview images (`net::ERR_FAILED` in `_network_image_web.dart`). Confirmed via
investigation: this only affects web (native `dart:io` HTTP doesn't enforce CORS),
and every `Image.network` call site in the link-preview widgets
(`lib/app/layouts/conversation_view/widgets/message/interactive/`) already has an
`errorBuilder`/`onError` fallback. No action needed unless it starts looking broken
visually, not just noisy in the console.

## Suggested order to keep working

1. ~~Verify the chat-list sort fix live, commit, push.~~ Done.
2. ~~Contacts — apply the fixes already identified above.~~ Done, verified live.
3. Photo downloading — not investigated at all yet. Next up.

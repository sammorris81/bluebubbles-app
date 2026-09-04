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

### 3. Photo downloading — one confirmed bug fixed, default path reviewed but not live-verified
Started this session. Read through the full download pipeline for web: `AttachmentHolder`
(`lib/app/layouts/conversation_view/widgets/message/attachment/attachment_holder.dart`) →
`MessagesService.loadAttachmentContent`/`_startAttachmentDownload`
(`lib/services/ui/message/messages_service.dart`) → `AttachmentsService.getContent`
(`lib/services/ui/attachments_service.dart`) → `AttachmentDownloadController.fetchAttachment`
(`lib/services/network/downloads_service.dart`) → `AttachmentApi.download`
(`lib/services/network/api/attachment_api.dart`) → rendering in `ImageViewer`
(`lib/app/layouts/conversation_view/widgets/message/attachment/image_viewer.dart`).

**Confirmed bug, fixed**: `AttachmentsService.getContent()`'s web branch collapsed two
unrelated conditions into one `else`: "bytes already cached" and "auto-download disabled" both
fell through to returning a `PlatformFile` with `bytes: attachment.bytes` — which is `null` in
the auto-download-off case, since nothing has fetched it yet. That fake "resolved" file then
got treated as complete content by `loadAttachmentContent` (`attState.updateResolvedFileInternal(content)`,
`updateIsDownloadedInternal(true)`), rendering as a permanently blank `SizedBox` in `ImageViewer`
(`file.bytes == null`) with no way to retry — `AttachmentHolder._buildOnTap` returns `null`
whenever `resolvedFile.value != null`, regardless of whether that "resolved" file actually has
data. Net effect: with the **Auto Download** setting turned off, every image on web renders as a
blank, untappable box forever. Fixed by splitting the branch so "no bytes and auto-download off"
falls through to returning the bare `Attachment` instead, matching native's behavior — this
makes `loadAttachmentContent` show the normal tap-to-download placeholder.
Auto Download defaults to `true`, so this doesn't affect a fresh install, only accounts that
have explicitly disabled it.

**Default path (Auto Download on) reviewed, not live-verified**: traced the full chain by hand
and it looks correct — `getContent` starts an `AttachmentDownloadController` when
`attachment.bytes == null`, `fetchAttachment()` requests with `savePath: null` so
`AttachmentApi.download` uses `ResponseType.bytes` instead of streaming to a file, and
`_processDownloadedFile` stores the result on `attachment.bytes` and wraps it in a `PlatformFile`
that `ImageViewer` renders via `Image.memory`. Also worth noting: `AttachmentState`'s constructor
seeds `transferState` from `attachment.isDownloaded` (the *server's* flag, stale/irrelevant on
web since bytes are always empty after a fresh page load) — currently harmless because nothing
short-circuits on `transferState == complete` without also checking `resolvedFile != null`, but
it's a latent trap if that ever changes.

**Could not live-verify with a real photo this session.** Every chat in this account either had
no attachments in its loaded history or wasn't reachable (see below), and sending a fresh test
photo requires the browser's native file-picker dialog, which the Claude-in-Chrome tooling
cannot drive here — the click reaches the app fine and opens the chooser, but the chooser itself
runs outside anything `find`/`read_page`/`file_upload` can see or fill (no `<input type=file>`
ever shows up in the accessibility tree, and `file_upload` requires a `ref` to one). Confirmed
the account's own number for self-testing via Settings → iMessage Profile: `+19193574218`.
Successfully created a fresh 1:1 chat with "Sam Morris" (self) and sent a **text-only** test
message ("test photo download") to confirm the compose flow at least works end to end
(self-messages loop back near-instantly and show `Read`) — but never got a real image attached
to it. If picking this up again: either have the user attach a photo manually from the live
browser session, or find/create a message with an attachment some other way (the REST API
directly, or a phone-side send) rather than fighting the file picker again.

**Separate bugs noticed along the way (not fixed, not part of this task)** — all look like the
same root cause: something silently swallows a `LateInitializationError` from an unguarded
`Database`/ObjectBox call on web, leaving the awaiting UI parked in an infinite spinner instead
of erroring or completing:
- The conversation list sidebar does not respond to scroll (mouse wheel, click-drag) at all —
  chats past the visible viewport are simply unreachable from the sidebar.
- Message search (search icon → type a query → submit) shows an indefinite spinner and never
  returns results or a "no results" state.
- Starting a "New Message" to a name/number that matches an *existing* conversation with more
  than the two participants tried (e.g. a 3+ person group chat) gets stuck forever on "Loading
  surrounding message context..." (`lib/app/layouts/conversation_view/pages/messages_view.dart`).
  A fresh 1:1 chat (no existing match) does not hit this — it's specific to jumping into
  pre-existing message context.
Console repeatedly logged (unprompted, on a timer) `LateInitializationError: Field 'messages' has
not been initialized`, `LateInitializationError: Field 'store' has not been initialized`, and a
failing `Incremental Chat Sync`/`IncomingMessageHandler` — all consistent with recurring
background sync code that isn't `kIsWeb`-guarded the way the contacts sync now is. Worth a
dedicated session; did not chase this further since it's outside today's attachment-focused
scope.

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
3. Photo downloading — one real bug found and fixed (auto-download-off path), see above.
   The default (auto-download-on) path was reviewed by hand and looks correct but was never
   exercised against a real image in the browser this session. Get a real attached photo into
   a test chat (see notes above on why the file picker couldn't be automated) and confirm the
   `Image.memory` render actually works end to end before calling this fully verified.
4. New: the scroll/search/"loading surrounding context" hangs noted above — likely one shared
   root cause (an unguarded `Database` call on web whose `LateInitializationError` is silently
   swallowed). Not part of today's attachment work; worth its own session.

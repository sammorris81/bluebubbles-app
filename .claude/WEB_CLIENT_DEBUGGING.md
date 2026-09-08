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

Three gotchas that cost time before:

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

**Third gotcha, and it invalidates test results: the Claude-in-Chrome `computer` tool's
`scroll` action does not scroll Flutter web at all.** Its synthetic scroll never reaches
Flutter's pointer pipeline — instrumenting the widget tree with a root-level `Listener`
showed *zero* pointer events of any kind (no `PointerSignal`, no `PointerPanZoom`, no
`PointerMove`) during a `scroll` call, while `left_click` on the same spot logged a
`PointerDownEvent` normally. Nothing scrolls, anywhere in the app, via that action. It is
very easy to misread this as "this list is broken" — especially right after opening a chat,
where the message view auto-scrolls to the bottom on load and the resulting screenshot looks
like the wheel worked.

To actually test scrolling, dispatch a real `WheelEvent` at Flutter's glass pane with the
`javascript_tool` (coordinates are CSS pixels, which match Flutter's logical pixels):

```js
const gp = document.querySelector('flt-glass-pane');
let consumed;
for (let i = 0; i < 5; i++) {
  const ev = new WheelEvent('wheel', {
    clientX: 226, clientY: 565, deltaY: 120, deltaMode: 0,
    bubbles: true, cancelable: true, composed: true, view: window,
  });
  gp.dispatchEvent(ev);
  consumed = ev.defaultPrevented;
}
consumed; // true means Flutter handled the event
```

Use a negative `deltaY` to scroll up. Note screenshot
coordinates are *not* CSS pixels — on this setup the screenshot frame is 1231x980 while
`window.inner{Width,Height}` is 1159x923, a 1.062x factor. Divide screenshot coordinates by
that before using them as `clientX`/`clientY`.

Related: **mouse click-drag never scrolls a Flutter list, on web or desktop.** `main.dart`'s
`scrollBehavior` passes `dragDevices: Platform.isLinux || Platform.isAndroid ? ... : null`,
and `copyWith(dragDevices: null)` keeps `MaterialScrollBehavior`'s default of
`{touch, stylus}` — mouse is deliberately excluded by Flutter. That is upstream behavior, not
a web bug; don't treat "click-drag doesn't scroll" as a symptom.

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
- ~~The conversation list sidebar does not respond to scroll (mouse wheel, click-drag) at all —
  chats past the visible viewport are simply unreachable from the sidebar.~~ **Not a bug — this
  was a tooling artifact.** See "Sidebar scroll — investigated, no bug found" below.
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

### Group chat titles not resolving to contact names — fixed and verified live (affects ALL platforms)
(Follow-up to the contacts fix below. Reported by the user: `+16087990697` and
`+19204122065` — the second participant in two different group chats — never
resolved to a name, even though the matching contact ("Angela House", "Timothy Dale")
genuinely existed and every 1:1 chat's contact resolution worked fine.)

**Not a web-only bug.** Root cause is in `lib/app/state/handle_state.dart`, which is
shared, platform-agnostic code — this affects native and desktop too, just harder to
hit there since a full contact sync usually completes before any UI renders.

Root cause: `HandleState.updateFromHandle()` called `updateDisplayNameInternal()`
*first*, before `_recomputeReactionDisplayName()` and `updateFormattedAddressInternal()`.
`ChatState`'s `ever(hs.displayName, ...)` listener (which recomputes the chat title)
fires *synchronously* the instant `displayName` changes — so by the time it ran,
`reactionDisplayName` and `formattedAddress` hadn't been updated yet. For a 1:1 chat
this didn't matter (`_computeTitle()`'s DM branch reads `displayName.value` directly,
already fresh). For a **group** chat, `_computeTitle()` falls back to
`chatCreatorSubtitle`, computed by `_computeCreatorSubtitle()` → `_shortNameFor()`,
which reads `reactionDisplayName.value` — still the *stale* pre-sync value at the
moment the listener ran. Nothing ever re-triggered the computation afterward once
`reactionDisplayName` caught up, since no listener was bound to *that* field.

Diagnosed by temporarily instrumenting the full chain (contact fetch → address
normalization → handle matching → `HandleState`/`ChatState` update) with targeted
logging for the two affected numbers, live in the browser. This proved, in order:
the contact *was* being fetched from the server correctly (including a same-person
duplicate under two source IDs — a numeric one and a macOS `ABPerson` UUID, itself
just a server-side dedup quirk, not a client bug); the address-normalization/matching
logic *did* find and attach the right contact to the right `Handle` object (verified
by object identity, not just address, across the whole pipeline); `HandleState`'s
`displayName` *did* update to the correct name and its `ever()` listener *did* fire —
but `_computeCreatorSubtitle()` inside that listener read a different, not-yet-updated
field. Fixed by reordering `updateFromHandle()` so `updateDisplayNameInternal()` —
the one field `ChatState` listens on — runs *last*, after every other field it might
transitively depend on.

**Verified live**: after the fix, "Adam & +16087990697" now reads "Adam & Angela" and
"Adam & +19204122065" now reads "Adam & Timothy" — no console errors.

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

### Contact photos (avatars) not loading on web — fixed and verified live
(Follow-up to the contacts fix above — names/matching worked, but every avatar still
showed initials or a gradient circle, never a real photo.)

Root cause was four independent, deliberate gaps stacked on top of each other — not
one bug, three "we'll deal with this later" decisions plus one that was just never
built:
1. `ContactV2Actions._syncContactsToHandlesInternal` called
   `HttpSvc.contact.fetchAll(withAvatars: !kIsWeb)` — on web this evaluates to
   `false`, so the server was never even asked for avatar data
   (`extraProperties=avatar` was omitted from the request entirely).
2. Even with avatar data, `_saveContactAvatar` writes to disk via
   `FilesystemSvc.appDocDir`, which is never initialized on web — the old code
   explicitly skipped this and recorded `avatarPaths[contactId] = null`.
3. `ContactV2` (both `database/io/contact_v2.dart` and, critically, the *actual* web
   model at `models/html/contact_v2.dart` — see the note below) only had an
   `avatarPath` file-path field, no field to hold decoded bytes in memory. There was
   nowhere to put a downloaded avatar even if one had been fetched.
4. `ContactAvatarWidget` unconditionally called `Image.file(File(contactV2Avatar))`
   with no `kIsWeb` branch — even a `path`-shaped placeholder wouldn't have rendered.

**Important gotcha hit while investigating**: `lib/database/io/contact_v2.dart` is
*not* the class used on web, despite `io/CLAUDE.md` saying io/ entities are "not used
on web." `lib/database/models.dart` conditionally exports
`models/html/contact_v2.dart` instead on `dart.library.html`. Anyone touching
`ContactV2` needs to check both files — they're meant to mirror each other's public
API so shared widget code compiles against either.

Fix (mirrors the `Attachment.bytes` in-memory-on-web pattern already established for
attachment downloads):
- `lib/models/html/contact_v2.dart` — added `Uint8List? avatarBytes` field (the real
  fix; this is the class actually compiled in on web).
- `lib/database/io/contact_v2.dart` — added the same field as `@Transient()` (always
  null on native/desktop, which still uses `avatarPath`) purely so shared widget code
  referencing `contactV2.avatarBytes` compiles on both platforms without a `kIsWeb`
  cast at every call site.
- `lib/services/backend/actions/contact_v2_actions.dart` — `fetchAll(withAvatars:
  true)` unconditionally now; on web, decodes the base64 `avatar` field into
  `avatarBytes` directly on the in-memory `ContactV2` instead of skipping it.
- `lib/app/state/handle_state.dart` — added `avatarBytes` as an `Rxn<Uint8List>`
  alongside the existing `avatarPath` `RxnString`, resolved from
  `handle.contactsV2.firstOrNull?.avatarBytes` (mirrors `_resolveAvatarPath`'s
  structure, inverted: null on native, populated on web). Wired into
  `updateFromHandle`, `redactAvatars`/`unredactAvatars` alongside the existing path
  handling.
- `lib/app/components/avatars/contact_avatar_widget.dart` — added a `cachedAvatarBytes`
  read (same `_handleState ?? contactV2` fallback as `cachedAvatarPath`) and a new
  `Image.memory(...)` branch, inserted between the existing `Image.file` branch and
  the initials fallback. On native `cachedAvatarBytes` is always null so this branch
  never triggers; on web `cachedAvatarPath` is always null so it falls through to this
  one whenever bytes are available.
- `lib/app/components/avatars/contact_avatar_group_widget.dart` — the "show contacts
  with photos first" sort heuristic (`_sortedHandles`) only checked `avatarPath`;
  updated to also check `avatarBytes` so it doesn't misorder group avatars on web.

**Verified live**: after the fix, the `/api/v1/contact` request now includes
`extraProperties=avatar` and returns in ~70-90ms for 474 contacts (no noticeable
slowdown in this account). Real photos now render for contacts with one (confirmed
visually: "Sam Morris", "Vickie Woodard (Weber)", and group avatars like "Adam &
+16087990697" showing a real photo for the participant who has one and initials for
the one who doesn't) — no console errors from the base64 decode or `Image.memory`
render path.

**Known remaining gap, not fixed (minor, cosmetic)**: `conversation_list.dart`'s
avatar precache warm-up (`precacheImage(ResizeImage(FileImage(File(path)), ...))`)
only handles `avatarPath` and is a no-op on web — chat tiles scrolling into view may
show a brief cold-decode flash before the `Image.memory` frame lands, where native
wouldn't. Not fixed since it's a minor perf/polish detail, not a "photos don't load"
bug.

### Link-preview CORS image errors — cosmetic, no fix needed
Browser console showed CORS-blocked image loads for `share.1password.com` Open Graph
preview images (`net::ERR_FAILED` in `_network_image_web.dart`). Confirmed via
investigation: this only affects web (native `dart:io` HTTP doesn't enforce CORS),
and every `Image.network` call site in the link-preview widgets
(`lib/app/layouts/conversation_view/widgets/message/interactive/`) already has an
`errorBuilder`/`onError` fallback. No action needed unless it starts looking broken
visually, not just noisy in the console.

### Pin chats via right-click — fixed and verified live (feature was disabled, not broken)
User asked how to pin favorite chats on web (works on Android). Investigation found the
entire pin data path already worked cross-platform — `ChatState.isPinned`/`pinIndex`,
`ChatsSvc.setChatPinned`, `Chat.togglePinAsync`, and the chat-list sort/section logic in
`chats_service.dart` and `database/html/chat.dart` all handle it fine. The right-click
menu item itself was just gated `if (!kIsWeb)` in `showConversationTileMenu`
(`lib/helpers/ui/ui_helpers.dart`), alongside Mute/Archive/Delete. Removed the gate for
Pin only (left Mute/Archive/Delete gated — out of scope for this ask).

Note: on web there's no local ObjectBox DB, so `Chat.saveAsync()` is a no-op there —
pin state lives only in the in-memory `Chat`/`ChatState` for the session and resets on
page reload/hot-restart. This mirrors how mute/archive/etc. already behave on web, so
it wasn't treated as a blocker.

**Found and fixed along the way — a real bug affecting every web right-click menu,
not just this one**: `onSecondaryTap` handlers (`conversation_tile.dart`,
`message_popup_holder.dart`, `settings_tile.dart`) each independently did
`if (kIsWeb) { (await html.document.onContextMenu.first).preventDefault(); }` before
showing their popup. This races the browser's real event order — Chromium fires the
native `contextmenu` DOM event *before* the `mouseup` that drives Flutter's
`onSecondaryTapUp` — so by the time each handler started listening, the event it
wanted had already passed. It always ended up suppressing the *next* right-click's
native menu instead of the one that triggered it, so every web context menu
(chat tile, message popup, settings tile) required two right-clicks: the first
click's popup only appeared once a second right-click's `contextmenu` event resolved
the stale listener. Confirmed live in the browser — reproduced the two-click
requirement, then confirmed a single click works after the fix.

Fix: replaced the three per-widget racy listeners with one global
`html.document.onContextMenu.listen((event) => event.preventDefault())` registered
once in `main.dart`'s `kIsWeb` startup block, so the browser's native menu is
suppressed app-wide up front rather than reactively per right-click.

**Verified live** against `http://10.7.12.13:8090/web`: single right-click on a chat
tile now shows Pin/Mark Unread immediately; clicking Pin moves the chat into the
pinned section at the top with correct avatar/name rendering; Unpin round-trips back.

### Message search hang — root-caused and fixed (one of two causes; local search still N/A on web)
This confirms item 5 below: user reported a search for a contact name ("Lisa") never
returned anything. Root cause found in `SearchQueryHelper.runNetwork`
(`lib/app/layouts/conversation_list/pages/search/search_query_helper.dart`): after
fetching results from the server, it unconditionally ran
`Database.chats.query(Chat_.guid.oneOf(chatGuids)).build().find()` to swap in the
locally-cached `Chat` objects — on web `Database.chats` is an uninitialized `late
final` (no ObjectBox), so this threw `LateInitializationError` on every network
search. `search_view.dart`'s `search()` awaited this with no try/catch, so the
exception left `isSearching` stuck at `true` forever — an indefinite spinner with no
error surfaced, matching the originally reported symptom exactly. (Web has no local
search toggle — `local.value` defaults to `false` and `local_search_web.dart` is a
stub — so every web search goes through this `runNetwork` path.)

Fix:
- `search_query_helper.dart`: on `kIsWeb`, look up each chat via
  `ChatsSvc.getChatState(guid)?.chat` (in-memory, already hydrated from the server)
  instead of querying `Database.chats`.
- `search_view.dart`: wrapped the local/network search calls in `search()` in a
  try/catch that logs via `Logger.error(...)` — a defensive fix so any *other* future
  exception on this path fails visibly (empty results) instead of hanging the spinner
  forever again.

**Verified live**: searching "Lisa" now returns real matches instantly (chat titles
and message snippets with "Lisa" highlighted), confirmed against
`http://10.7.12.13:8090/web` after a hot restart.

**Search filters verified correct** (user asked specifically): tested all four —
From You / Not From You (produce correct, distinct complementary result sets —
confirmed by comparing which specific messages appear in each), Filter by Chat
(restricts correctly to only the selected chat's matches), and Filter by Date
(a "since 9/4/2025" filter correctly excluded all older matches). All results were
verified against the actual message content/dates shown, not just "some results
appeared." No filter correctness issues found.

**Separate, not-fixed, likely-not-web-specific UI quirk noticed while testing**: the
small arrow "submit" button next to the search field (`ConversationSearchField`,
`lib/app/layouts/conversation_list/pages/search/conversation_search_field.dart`)
often needs two clicks to register after selecting a filter chip — the first click
does nothing visible, the second submits. Reproduced consistently in the browser.
Tried changing its `suffixMode` from `OverlayVisibilityMode.editing` to `.always`
(theory: losing focus when the filter panel opens hides/disables the suffix), but
the double-click requirement persisted identically even with the button already
visible, so that theory was wrong and the change was reverted (see git history if
picking this up — not worth guessing further without deeper investigation into
`CupertinoTextField`'s internal gesture arena for its `suffix` slot). Does not block
search — pressing Enter/Return in the field submits reliably on the first try, and
this reproduces independent of the `Database.chats` fix above. Likely not
web-specific (the widget isn't platform-gated) — worth checking on native/desktop
before spending time on it.

### Pin/mute/archive reset on page reload — fixed (web-only localStorage persistence)
User noticed after the pin-on-web fix above: pinning a chat worked, but didn't
survive a page reload. Root cause: pin/mute/archive have never been synced to the
BlueBubbles server on *any* platform (confirmed by reading `ChatInterface.saveChat`
→ `ChatActions.saveChat` — it's a pure local-DB write, no HTTP call) — they're
purely per-device settings, persisted via the local ObjectBox DB on native/desktop.
Web has no local DB, so `Chat.saveAsync()`/`save()` were no-ops there, meaning this
state only ever lived in memory for the page session.

Fix, in `lib/database/html/chat.dart` (the file `database/html/CLAUDE.md` calls
"read-only stubs" — but this file already carries substantial real web-specific
logic beyond a stub, e.g. `webSyncParticipants`, so extending it here is consistent
with its actual content, not a new precedent):
- Added a small private `_WebChatOverrides` helper backed by `html.window.localStorage`
  (key `bb_web_chat_overrides`), storing a JSON map of `guid -> {isPinned, pinIndex,
  isArchived, muteType, muteArgs}`. A chat's entry is written whenever any of those
  fields differ from default, and removed entirely once they're all back to default
  (keeps storage from growing unbounded with stale entries).
- `Chat.fromMap()` calls `_WebChatOverrides.apply(chat)` after construction, so any
  chat loaded from the server picks up its persisted local override.
- `save()` and `saveAsync()` both call `_WebChatOverrides.save(this)` unconditionally
  — simpler and more robust than threading through the per-field `updateXxx` flags,
  and correctly covers every call path (the three toggle methods, plus pin-index
  drag-reorder via `ChatsSvc.setChatPinIndex`, plus the sync toggle variants used
  internally for temporary-mute auto-expiry).
- This is scoped to `localStorage`, so it's per-browser only (not synced across
  devices/browsers) — the same "per-device" characteristic these settings already
  have natively, just narrowed one level further to "per-browser."

Also un-gated the Mute and Archive items in the right-click menu
(`showConversationTileMenu`, `lib/helpers/ui/ui_helpers.dart`) for web, matching the
Pin item fixed earlier — there was no point persisting mute/archive state if there
was no web UI to ever set it. Archived chats are already reachable on web via the
existing "..." overflow menu → Archived (not platform-gated), so unarchiving a
chat someone archives on web isn't a dead end.

**Verified live**: pinned "Sam Morris", muted "+1 64357", and archived
"+1 833-315-1158", confirmed all three in `localStorage`
(`{"any;-;+19193574218":{"isPinned":true},"any;-;64357":{"muteType":"mute"},...}`),
then did a real page reload (fresh `navigate`, not hot restart) — all three
persisted correctly: pin still at top, mute icon still showing on the tile, and the
archived chat still absent from the main list but present under Archived. Reversed
all three afterward and confirmed the `localStorage` entry cleared back to `{}`.

### Replies/delivered/read receipts not updating live in an open conversation — fixed and verified live
Reported by the user: sending worked fine, but while actively viewing a conversation,
incoming replies, "Delivered", and "Read" status only appeared after navigating away
from the chat and back in. This is the same root-cause family as item 5 above (an
unguarded `Database`/ObjectBox call throwing on web, silently swallowed), just hitting
a different call path.

Root cause: `Chat.findOne` and `Message.findOne` (`lib/database/html/{chat,message}.dart`)
were both hardcoded to always return `null` — apparently on the assumption that shared
code would use the (already-existing) async `findOneWeb`/`findOneAsync` variants instead,
but `IncomingMessageHandler` (`lib/services/backend/incoming_message_handler.dart`,
shared with native/desktop, no web awareness) calls the plain sync `findOne` throughout:
- `_processUpdatedMessage()` used `Message.findOne(guid: ...)` to look up the message a
  delivery/read receipt applies to. Since this always returned `null` on web, every single
  `updated-message` event looked like it had no matching record, so it was parked via
  `_parkPendingUpdate()` and never applied — `_dispatchUpdatedMessage()` (the call that
  actually flips `dateDelivered`/`dateRead` on the `MessageState`) was never reached. A
  10s expiry timer just re-tried and re-parked it, forever, once per open chat message.
- `_hydrateChat()` used `Chat.findOne(guid: ...)` to short-circuit when the chat was
  already loaded. Since it always returned `null`, this early-return path was dead code
  on web, and *every* incoming message/update fell through to
  `ChatInterface.bulkSyncChats()`, which unconditionally calls
  `Database.chats.getMany(chatIds)` (`lib/services/backend/interfaces/chat_interface.dart`)
  — `Database.chats` is an uninitialized `late final` box on web, so this threw
  `LateInitializationError` on *every* incoming new message, before `chat.addMessage()`
  (the call that actually saves the message and fires the reactive update) ever ran. The
  exception was swallowed by `IncomingMessageHandler`'s generic `catchError` with no
  rethrow and no UI signal.
- A secondary instance of the same gap: messages loaded via history sync when a chat is
  opened (`SyncInterface.bulkSyncData`'s web branch) were built with `Message.fromMap()`
  directly, bypassing `Message.save()` — so they were never registered anywhere
  `Message.findOne` could find them either. A late-arriving receipt for one of those
  (e.g. from before this browser session started) would hit the exact same "no DB
  record yet" parking bug, forever, once per message. Confirmed live via the console
  spamming an identical "buffering"/"expired after 10s" cycle every 10 seconds for one
  fixed message GUID with no end in sight, for a message that predated the session.

Fix (four files):
- `lib/database/html/chat.dart` — `Chat.findOne` now delegates to `ChatsSvc.findChatByGuid`/
  `findChatByChatIdentifier` (the same in-memory lookup `findOneWeb` already used, just
  made synchronous) instead of unconditionally returning `null`.
- `lib/database/html/message.dart` — added a private static `_registry` (`Map<String,
  Message>`) populated by every `save`/`bulkSave`/`bulkSaveNewMessages`/`replaceMessage`
  call (mirroring the exact points where `WebListeners.notifyMessage()` already fires),
  with entries removed on `delete()` and on GUID swap in `replaceMessage()`. `findOne`
  now reads from this registry instead of returning `null`. Added
  `Message.registerKnown(Iterable<Message>)` to backfill the registry for messages
  loaded via a path that doesn't call `save()`.
- `lib/database/io/message.dart` — added a no-op `Message.registerKnown()` mirror (native
  has a real ObjectBox-backed `findOne`, no registry needed) purely so the shared caller
  below compiles on every platform, matching the existing `findOneWeb`-on-io pattern.
- `lib/services/backend/interfaces/chat_interface.dart` — `bulkSyncChats()` now has a
  `kIsWeb` branch that hydrates chats directly from the map data already passed in
  (`Chat.fromMap`) instead of touching `Database.chats`, for the remaining case
  `_hydrateChat` still falls through to bulk-sync (a brand-new chat, or a group-event
  message) — best-effort (no handle-matching/persistence), just enough to not crash.
- `lib/services/backend/interfaces/sync_interface.dart` — `bulkSyncData()`'s existing
  `kIsWeb` branch now calls `Message.registerKnown()` on the messages it builds, fixing
  the secondary gap above.

**Verified live** against `http://10.7.12.13:8090/web` (self-chat with own number,
`+19193574218`): sent a message, watched it stay unread with no status, then — without
navigating away from the conversation — watched the echoed reply arrive as an incoming
bubble and the sent bubble's status change to "Read", all in place. Console logs during
this showed the `new-message`/`updated-message`/`chat-read-status-changed` socket events
being processed cleanly with no `LateInitializationError` and no "no DB record yet —
buffering" loop (confirmed by contrast against a run on the pre-fix build, which showed
exactly that loop, once per 10s, forever, for the same kind of event).

### Sidebar scroll — investigated, no bug found (was a tooling artifact)
Carried forward as an open bug from the attachment session's "noticed along the way" list:
"the conversation list sidebar does not respond to scroll (mouse wheel, click-drag) at all."
Investigated directly and **could not reproduce it — the sidebar scrolls correctly.**

How it was established, since "I scrolled and nothing moved" was exactly the false signal that
created this entry in the first place:
- Instrumented `cupertino_conversation_list.dart` (the iOS skin is the active one here) with a
  `Listener` wrapping the sidebar's `ScrollbarWrapper`, logging `onPointerSignal` and
  `onPointerDown` plus the `iosScrollController`'s live `maxScrollExtent`/`pixels`, and added a
  second `Listener` at the app root in `main.dart` logging *every* pointer event type.
- With the Claude-in-Chrome `scroll` action: `onPointerDown` fired on click, but **no pointer
  event of any kind** was logged for a scroll — at the sidebar or at the app root. The scroll
  action simply doesn't reach Flutter (see the gotcha under "How to run it").
- With a real `WheelEvent` dispatched via `javascript_tool`: the sidebar scrolled perfectly.
  Logs showed `_TransformedPointerScrollEvent` arriving with `hasClients=true`,
  `maxScrollExtent=17124`, `physics=AlwaysScrollableScrollPhysics`, `axisDirection=down`, and
  `pixels` advancing `0 → 120 → 240 → 360 → 480` across five ticks, with the list visibly
  moving in the screenshot. Scrolling back up clamped correctly at `0`, and it worked from the
  header region, the middle, and the bottom of the sidebar alike.

The "click-drag" half of the original report is upstream Flutter behavior (mouse is not a drag
device — see "How to run it"), identical on desktop native. So there is nothing web-specific
here and no fix was made.

Two things reviewed while in here and deliberately left alone, since neither causes this and
neither is web-specific — worth knowing about if this area is touched again:
- `material_conversation_list.dart`'s `NotificationListener(onNotification: ...)` returns `true`,
  which *stops* `ScrollNotification`s from propagating to ancestors rather than merely observing
  them (`false` is the "keep bubbling" return). Harmless today because nothing above it consumes
  them, but it is the opposite of what the code reads like it intends.
- `ScrollbarWrapper` wraps web and desktop in `ImprovedScrolling` from
  `flutter_improved_scrolling` 0.0.4 with `enableCustomMouseWheelScrolling` left at its default
  of `false`, so its `onPointerSignal` handler is inert and wheel events pass straight through to
  the `Scrollable`. It is not in the path for this.

## Suggested order to keep working

1. ~~Verify the chat-list sort fix live, commit, push.~~ Done.
2. ~~Contacts — apply the fixes already identified above.~~ Done, verified live.
3. Photo downloading — one real bug found and fixed (auto-download-off path), see above.
   The default (auto-download-on) path was reviewed by hand and looks correct but was never
   exercised against a real image in the browser this session. Get a real attached photo into
   a test chat (see notes above on why the file picker couldn't be automated) and confirm the
   `Image.memory` render actually works end to end before calling this fully verified.
4. ~~Contact photos (avatars) not loading.~~ Done, verified live.
5. ~~New: the scroll/search/"loading surrounding context" hangs noted above~~ — partially
   resolved. Search was root-caused and fixed (see above). Sidebar scroll turned out not to be a
   bug at all (see "Sidebar scroll — investigated, no bug found"). The remaining item is the
   "New Message" → existing 3+ person group chat hang on "Loading surrounding message context",
   which still looks like the unguarded-`Database`-call-on-web family.

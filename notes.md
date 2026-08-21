<!--
SPDX-FileCopyrightText: 2026 Mein1337
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Notes

Notes that are expensive to rediscover.

Everything here records *why* the code is shaped the way it is: a quirk of the
Matrix protocol, a limitation in the SDK, a platform trap, or a decision that
looks arbitrary until you know what it was avoiding. It is not API
documentation - the code already says what it does. This file exists so that
whoever next touches one of these areas, very likely the author, does not have
to work the same thing out a second time.

Each section names where its code lives.

## Activity summary

Code lives in `lib/features/activity/`.

### The log exists because the SDK cannot answer the question

"What has been said recently, across every room" has no API. `Room.lastEvent`
gives exactly one event per room, and anything richer means opening a `Timeline`
per room — five live stream subscriptions each, for rooms nobody is looking at,
with decryption running behind them.

So `MessageActivityLog` accumulates the answer instead, from
`client.onTimelineEvent`, which is every room's timeline **after decryption**.
Three consequences worth knowing:

- **It starts nearly empty.** Seeding from each room's `lastEvent` costs nothing
  (the SDK already persists it for the room-list preview) and means a cold start
  is not blank, but it is one message per room. Everything else fills in as the
  app runs. That is what the opt-in backfill in settings is for.
- **It is not persisted, deliberately.** Writing it would put decrypted message
  bodies into `shared_preferences`. Re-asking the server is the better trade.
- **The record holds no names.** `MessageRecord` stores ids and a preview;
  display names and avatars are resolved when a row is drawn. Matrix loads room
  members lazily, so a message captured during the first sync usually knows its
  sender only as `@alice:example.org` — freezing that in would leave the summary
  showing raw ids for the rest of the session.

### The backfill filters server-side, which is what makes it cheap

Each room gets one `/messages` call carrying a filter with **`senders`** set to
the follow list, and `types` set to both `m.room.message` *and*
`m.room.encrypted`. Both types are needed: in an encrypted room the wire type is
the latter, so filtering on `m.room.message` alone comes back empty from exactly
the rooms most worth fetching. Because the server does the filtering, a limit of
20 events per room is spent entirely on people being followed rather than on the
room's general traffic.

Decryption is `Event.fromMatrixEvent` then `client.encryption.decryptRoomEvent`,
the same sequence `Room._refreshLastEvent` uses internally. History no megolm
session is held for comes back still typed `m.room.encrypted` and is dropped —
an undecryptable placeholder in a summary is worse than an absence, because
there is nothing to be done about it.

The run is **sequential**. Tens of `/messages` calls fired at once is how you
meet `M_LIMIT_EXCEEDED`; the user opted into a slower start, not into being
rate-limited. Per-room failures log and continue.

### Prefs are read once, not watched

`MessageActivityLog.build()` uses `ref.read` on the activity prefs rather than
`ref.watch`. Watching would tear the whole notifier down — subscription, records
and all — every time a toggle was flipped in settings, which is the one moment
somebody is definitely looking at the page. Live changes reach the feature
through the derived providers, which do watch.

### Something has to start it

The log is not auto-dispose, but a Riverpod provider is still built lazily on
first read. Without something reaching for it at start-up it would only begin
collecting when the page was first opened, and so be empty every time anyone
looked at it. `ActivityLogKeepAlive` is a zero-sized widget in the shell that
does this with `ref.listen`, not `ref.watch`: watching would rebuild the shell
on every message in every room, while listening still registers a real
subscription — which is what makes the provider rebuild when the client is
swapped on an account switch, and its `onDispose` fire to cancel the old stream.

### Scrolling to a message without a positioned-list package

The message list is a `ListView.builder` with no fixed extent, so there is no
offset to scroll to. `MessageList._reveal` does it in three steps: wait for the
timeline's first page (listener-driven, because opening a cold room takes a
second and frame-polling would burn a core to learn nothing), paginate until the
event is loaded (capped — a "recent" message is almost always on the first
page), then aim at `maxScrollExtent * index / items.length` and let
`Scrollable.ensureVisible` correct it once the real row exists.

The estimate is the builder delegate's own extrapolation from the children built
so far, which is exactly the average-row guess wanted here.

An event that is never found is **still highlighted**. The wash is what
identifies the message when the user scrolls to it themselves, and marking
nothing would make a failed jump indistinguishable from a jump to the wrong
place.

The highlight is accent-coloured and deliberately **not** the mention slots:
"someone said your name" and "this is the message you asked for" are different
facts, and sharing a colour would make every jump look like a mention.

### Unread counts come from the server, and only a receipt lowers them

`room.highlightCount` is not computed here — it is `unread_notifications.
highlight_count` off the sync, copied through by `RoomListItem.from`. The
homeserver lowers it when a read receipt moves past the events that raised it,
and at nothing else.

Nothing in this app sent one until now, which made every count **monotonic**.
Opening a room did nothing; a mention received once stayed badged until the same
account read that room in another client. `ReadReceiptSender` fixes that, with
two conditions that are the whole design:

- **At the newest end of the list.** Somebody scrolled up into history has not
  read what arrived underneath them.
- **The window is not hidden.** An unfocused but visible window still counts —
  on desktop that is a second monitor, which people do read — but a minimised or
  tray-ed one does not.

It also refuses to post a receipt for a room the server already considers read,
or the app would fire one on every room switch.

### A call ring is a doorbell that nobody withdraws

This is what put a red 1 on a room where nothing was said.

Starting a call sends **two** things. The membership state event is the one this
app reads. The other is a ring — `org.matrix.msc4075.rtc.notification`, an
ordinary timeline event carrying `m.mentions: {room: true}`. That mention is not
decoration: it makes the homeserver's `@room` push rule fire, which sets a
highlight tweak, which is a badge.

Three facts then conspire:

- **Leaving does not withdraw it.** Ending a call clears the *membership* to
  `{}`. The ring stays in the timeline for good.
- **Nothing rendered it.** `_isRenderable` in `message_grouping.dart` admitted
  `m.room.message` and seven state types. A ring is neither, so the badge
  counted an event the timeline refused to draw — a red 1 over an empty-looking
  room, with nothing on screen to explain it.
- **A ring has a lifetime.** MSC4075 has the sender state one; Element sends
  30 s. Past that it is describing something that already happened.

Two changes came out of that, and they are separate fixes to separate halves.

**The ring is now drawn**, as a system line — *"Alice started a call"*, with the
same green handset every other call affordance uses. The rule it establishes is
that **an event which can badge a room has to be visible in it**.

The call *membership* stays excluded, and that asymmetry is the point: it is
state, it changes on every join, leave and two-minute heartbeat, and drawing it
would bury the conversation under bookkeeping the room list already shows.
`isRenderableType` was split out of `_isRenderable` so both halves can be
pinned by a test without needing a `Room`, a `Client` and a database.

The wording is ours because the SDK has none for the type — it renders "Unknown
event org.matrix.msc4075.rtc.notification" — and, unlike a member event, the
body carries no actor, so the name is prefixed by hand. It deliberately does not
say *video* or *audio* call despite the ring carrying `m.call.intent`: in
captured traffic that field regularly contradicts the sender's own call
membership seconds later, so naming it would be confidently wrong about half the
time.

**The badge is now cleared** once the call is over, which is the rest of this
section.

`StaleRingSweeper` clears those. The delicate part is that a read receipt also
clears everything *before* the event it points at, so guessing is not an option
— which is why it asks **`/notifications`**, the one endpoint that says which
events actually produced each badge. `staleRingReceiptTarget` then refuses
unless it can prove the badge is only dead rings: nothing unread that is not a
ring, no ring still inside its lifetime, no live call in the room, and the
server's own highlight count no higher than the notifications it could see. Any
one of those failing leaves the room alone.

The receipt it sends is **private** (`m.read.private`). That clears our count
server-side, which is the point, while announcing nothing to the room —
broadcasting "read" for a doorbell nobody answered would be a claim about
messages that were never sent — and leaving `m.fully_read` where it was, so the
unread line in another client does not move.

It runs off the two clocks that already exist: the sync tick catches a call
*ending*, and the 30 second expiry tick catches a ring simply *aging out*, which
arrives as nothing at all because the caller may never have hung up. It
throttles itself to one request per 20 seconds and skips the network entirely
unless some room actually has a highlight, which is almost always.

### One timer, two questions

`voiceExpiryTickProvider` was written so a call membership could expire without
a sync arriving. "Spoke in the last 30 minutes" stops being true the same way —
silently, in a room producing no traffic — so the activity providers watch the
same 30 second sweep rather than adding a second timer. It remains the only
timer-driven provider in the app.

## Accounts and verification

Notes that are expensive to rediscover. Code lives in
`lib/features/accounts/` and `lib/features/settings/`.

### One live client, swapped — not several

`clientProvider` used to be a `ProviderScope` override, and its comment
explained that an override *cannot be rebuilt*, which is what stopped a second
`Client` from opening a second sqlite handle on the same file. Multi-account
made the client genuinely mutable, so that guarantee had to move rather than
disappear: `ActiveClientController` is now the only thing allowed to construct
or dispose a client, and the rule it enforces is that **no two live clients
share a storage key**.

Read sites did not change. `clientProvider` is still a `Provider<Client>`; it
just derives from the controller now. The one rule for callers is the one that
was always implied: `watch` it, never cache it.

### Each account owns a database, and that is where its session lives

Nothing stores an access token. The token is already inside each account's
`MatrixSdkDatabase`, so switching is `Client(storageKey).init()` and the
registry only has to remember which database belongs to whom, plus a cached
display name and avatar so a row can be drawn for an account whose client is
not running.

`matrix_bootstrap.dart` is the only place a storage key becomes a name on disk.
The key `default` maps to the original unsuffixed `matrix_client.sqlite`, which
is what adopts a pre-multi-account installation — the upgrade signs nobody out.
Keys are random rather than sequential so removing an account cannot make the
next one reuse a directory a slow teardown has not finished deleting.

### The order of an account switch is not arbitrary

`AccountActions.switchTo` leaves the call **first**, and awaits it. This cannot
be left to provider disposal: swapping the client rebuilds
`callControllerProvider`, and `LiveKitCallController.dispose` only fires
`unawaited(_teardown(...))` — which races the old client's teardown and loses,
leaving us advertised in a channel we are not in until the membership expires
hours later.

The new client is then built and initialised **before** the old one is
disposed, and only published once it is ready. Two clients coexist for a
moment, which is safe precisely because they are on different databases, and it
means a homeserver that is down leaves the user on the account they had rather
than on nothing.

Note `dispose()`, never `logout()`, when switching. `logout()` calls `clear()`,
which empties the store — switching away from an account would sign you out of
it.

`bootstrapProvider` deliberately watches the *boot* client rather than
`clientProvider`. A swapped-in client has already been initialised, and
re-entering `init()` on it throws `ClientInitPreconditionError` and drops the
whole app to its error screen.

### Verification is off unless `verificationMethods` is set

`KeyVerificationManager` returns early on **every** `m.key.verification.*`
to-device event while `Client.verificationMethods` is empty, which is its
default. Nothing logs anything; incoming requests simply never arrive. The
constructor in `matrix_bootstrap.dart` passes both `emoji` and `numbers`.

### `short_authentication_string` is an intersection, not a choice

This one silently made verification against Element impossible, and looked like
a bug in the protocol rather than in us.

Both sides send every SAS method they know. The SDK keeps the **intersection**
(`_calculatePossibleMethods`), so between two full clients emoji *and* decimal
are both agreed — and each end then independently decides which to draw. Both
derive from the same shared secret, so either is a complete check. Element
leads with emoji. We drew only digits. The result: two people staring at a
seven-emoji row and a twelve-digit number, unable to compare anything, with no
error anywhere because nothing was wrong.

So the dialog shows **one** code, chosen by a preference (Settings → Sessions &
Security → *Verification code*), defaulting to numbers — they are unambiguous
to read aloud, where emoji depend on two people naming the same picture the
same way. When the other end agreed to both, the dialog offers a one-click
switch, because that is the escape hatch for exactly this mismatch.

`resolveSasDisplay` is the rule, and the point of it is that **the preference
cannot override the protocol**: a method the peer never offered is not
renderable, so it falls back rather than showing an empty box. The in-dialog
switch is per-verification and is deliberately not written back — needing to
read someone's emoji once says nothing about which code is easier in general,
and a modal that silently rewrites a setting is a bad way to discover it
changed.

Emoji are rendered with their names underneath for the same reason Element
does: the glyphs differ per platform, and "rabbit" is comparable where two
drawings of a rabbit are not.

### The decimal SAS is twelve digits, and all of them are shown

`KeyVerification.sasNumbers` splits five shared bytes into three 13-bit values
and adds 1000, so it is always three numbers in 1000–9191 — twelve digits,
about 39 bits. There is no six-digit form of this; showing half the digits
would halve the strength of the comparison while looking identical.

We group them as **four groups of three**, Element groups them as three groups
of four. Same digits, read left to right. The dialog says so explicitly,
because a different-looking layout otherwise reads as a mismatch — and
"mismatch" is the one conclusion that must never be reached by accident.

`sas_digits.dart` asserts the input shape rather than regrouping blindly, so an
SDK change that produced something else fails loudly instead of rendering a
short code that still looks checkable.

### Why Element flags your messages: local verification signs nothing

This is the single most misleading thing in the whole feature, and it cost a
release to notice.

Element's per-message shield asks exactly one question: **is this device's key
signed by its owner's self-signing key?** It has not honoured legacy
device-to-device verification for years. So a session can be verified
everywhere in our UI and still be flagged in Element, because "verified" in our
store and "trusted" by everyone else are unrelated facts.

The SDK is explicit about it. `verifyKeysSAS` marks keys with
`setVerified(true, false)` — signing disabled, commented *"we don't want to
sign the keys juuuust yet"* — and publishes a signature only if
`crossSigning.isCached()`. Worse, `Client.isUnknownSession` is literally
`deviceKeys[deviceID]?.signed != true`, so an unsigned session makes the SDK
*skip its own `askSSSS` step* and jump to `done`. The result was a dialog
reporting success while nothing left the machine.

Two consequences are baked into the code now:

- `EncryptionStatus.ownDeviceSigned` is the field that answers "why does
  Element warn about me", and the sessions pane leads with it.
- The verification dialog resolves `signedWithAccountKeys()` before claiming
  anything, and says *"Verified on this device only"* when that is the truth.

### Setting cross-signing up is what makes the client standalone

An account that has only ever used this app has no cross-signing identity at
all, so there is nothing to unlock — it has to be created. `EncryptionSetup`
covers both directions:

- **`createRecovery`** drives the SDK's `Bootstrap` state machine: create a
  recovery key, create the three cross-signing keys, publish them, sign this
  device, turn on the message-key backup. Returns the recovery key, which is
  derived from a private key living only in memory — hence the dialog showing
  it once behind a confirmation checkbox.
- **`signInWithRecoveryKey`** is `crossSigning.selfSign`, for an identity that
  already exists. It unlocks secret storage, caches the keys, and signs *this
  device* with the self-signing key. That signature is the whole fix.

Two things about `Bootstrap` that are not obvious:

- **It hangs without a UIA listener.** Uploading cross-signing keys goes
  through `uiaRequestBackground`, which publishes to `client.onUiaRequest` and
  then waits forever. `_handleUia` answers the password stage; without it there
  is no error, no timeout, and nothing on screen to say why.
- **It never wipes.** Every `askWipe*` state is answered with `false`, and
  `askBadSsss` is turned into an error rather than accepted. Secret storage can
  hold a message-key backup belonging to sessions we know nothing about, and
  overwriting it is not recoverable — not a decision to take inside a wizard.

`enableDehydratedDevices` defaults to false, so the `dehydratedDeviceSetup`
call the bootstrap makes outside its own try/catch is a no-op for us. Worth
knowing before turning that flag on.

### `Size.fromHeight` is an infinite minimum *width*

`FilledButton`'s theme carried `minimumSize: Size.fromHeight(44)`, which reads
as "44 tall" and means `Size(double.infinity, 44)`.

It survived unnoticed for two stages because every button in the app lived in a
`Column(crossAxisAlignment: stretch)`, which hands down a tight width that
clamps the infinity away. The first button placed in a **`Row`** broke: a Row
lays out non-flex children with unbounded main-axis constraints, nothing clamps
it, and layout throws `BoxConstraints forces an infinite width`.

The symptom looks nothing like a button problem. Layout aborts for the whole
subtree, so the pane is never laid out and never painted — a **blank screen**,
followed by a cascade of `RenderBox was not laid out`, `Cannot hit test a render
box with no size`, and mouse-tracker assertions as hit tests walk into
unsized boxes. It presented as "the Sessions tab renders blank", and it looked
intermittent only because that pane draws a spinner (no Row of buttons) until
`encryptionStatusProvider` resolves: the first open laid out fine, the second
had real content and died.

`test/theme/button_theme_test.dart` pins all three cases — a button in a Row, a
button in dialog actions, and the stretched Column that still has to produce a
full-width login button.

### The sync tick must not gate an async provider

`matrixTickProvider` fires every few hundred milliseconds while syncing. Its own
doc says everything else should be a synchronous snapshot derived from `client`
plus a watch on that counter — and every provider in the app follows it except
where this was got wrong once.

Making an **async** provider watch the tick means it is thrown back to
`AsyncLoading` several times a second. Anything rendering it with
`when(loading: …)` then shows a spinner essentially forever. The failure is
delayed and looks unrelated: the pane is correct on first open, because the
provider has just resolved, and blank on every open after, because by then the
tick has moved. That is what made the sessions pane appear to "render blank
after switching tabs".

`sessionsProvider` is therefore a plain `Provider<AsyncValue<…>>` that maps
`deviceListProvider`'s value; only a real `/devices` re-fetch can show a loading
state. `encryptionStatusProvider` has to stay async — `isCached()` awaits — so
it is read with `skipLoadingOnReload: true`.

### Only the requester may send the start

The most expensive bug in this feature, because everything reports success
while the two people are looking at different codes.

The SAS bytes come from an HKDF info string that names the **start** sender
first:

```
MATRIX_KEY_VERIFICATION_SAS|<starter>|<accepter>|<transaction id>
```

The SDK decides that order from `KeyVerification.startedVerification` — which
it sets in `sendRequest()`. So the flag actually means *"we sent the
request"*, and it is only the same thing as *"we sent the start"* when the
requester is also the starter.

Accepting a request and then sending a start breaks precisely that.
`acceptVerification()` leaves us in `askChoice`, and auto-continuing from there
sends a second start — the requester has already sent one. The SDK resolves the
glare by sorting `userId|deviceId` and letting the smaller win. If **our** start
wins we are the starter while the flag still says we are not, so we build the
info string in the opposite order to the other client:

- different SAS bytes → different emoji **and** different digits,
- the MAC at the end fails,
- Element reports *"Your messages are not secure — one of the following may be
  compromised"*, naming the homeserver and the network.

Whether it happens at all depends on how two device ids sort, which is what made
it look intermittent and environmental rather than like a bug in us.

So `_advance` returns early at `askChoice` unless `startedVerification` is true.
That is not a deadlock: with QR unadvertised, `isQrSupported` is false and the
SDK sends the start straight from its own ready handler, without asking the app.
The requester always starts; the accepter always waits. All four combinations of
(who started) × (which client) then agree.

### The states with exactly one sensible answer, and the one without

`askChoice` is auto-answered only on the requesting side, for the reason above.
QR is not advertised, so SAS is the only possibility and there is nothing to put
in front of the user.

`askSSSS` is deliberately **not** auto-answered any more. It used to call
`openSSSS(skip: true)`, which is what produced a green tick here and a warning
in Element with no way to connect the two. It is now a question — enter the
recovery key, or continue knowing the result is local-only.

The SDK calls `onUpdate` again from inside the very calls `_advance` makes, so
it tracks which state it last acted on — without that the auto-continue
re-enters itself and sends the same start event repeatedly. `EncryptionSetup`
guards its `Bootstrap` driver the same way, for the same reason.

## File attachments

Notes that are expensive to rediscover. Code lives in
`lib/features/chat/attachments/`.

### `Room.sendFileEvent`, never `Client.uploadContent`

`uploadContent` uploads **plaintext**. In an encrypted room that ships the file
to the server unprotected, with no error and nothing downstream able to tell.
The SDK's own doc says to use `sendFileEvent` for end-to-end encryption.

`sendFileEvent` also supplies, for free: the local echo, `fileSendingStatus`,
thumbnail generation with separate thumbnail encryption, the `m.upload.size`
pre-check, a retrying upload loop, the cache write that makes
`Event.sendAgain()` work later, and the `EventStatus.error` transition. All of
it arrives through the timeline's existing `onChange → notifyListeners` path,
so the feature added no new state plumbing to `TimelineController`.

### Captions are MSC2530, and the SDK does not expose them directly

`filename` holds the real name, `body` holds the caption when the two differ.
`sendFileEvent` spreads `extraContent` **last** into the event content, so
`extraContent: {'body': caption}` overrides the body while leaving `filename`
intact — exactly the right shape without hand-building content (which would
also mean reimplementing the encrypted-file block).

A caption belongs to *one* file. With several attachments the text is sent as
its own message ahead of them; putting it on the first would make Element render
it as a label for whichever image happened to lead.

### Classification ignores `hasAttachment`

`attachmentKindOf` deliberately switches on msgtype alone. The local echo that
`sendFileEvent` injects has neither `url` nor `file` until the upload finishes,
so gating on `hasAttachment` would render our own image as the text "sent a
picture" for a second and then pop into a thumbnail.

### Encrypted attachments cannot use `Image.network`

`Event.getAttachmentUri()` returns null for an encrypted attachment — the bytes
on the server are ciphertext. That null is the whole branch: when it comes back,
`downloadAndDecryptAttachment()` handles the download, decryption and caching.
One caveat: passing `getThumbnail: true` **throws** when no thumbnail exists,
hence `getThumbnail: event.hasThumbnail`.

### No byte-level upload progress exists

`FileSendingStatus` is a three-value enum (`generatingThumbnail`, `encrypting`,
`uploading`) and neither `sendFileEvent` nor `uploadContent` takes a progress
callback. The UI is indeterminate on purpose; a percentage would be invented.

### Videos we send have no poster frame

`Client.customVideoThumbnailGenerator` is not set and the SDK has no built-in
one, so our own videos render as a placeholder with a play glyph. Videos from
Element carry a thumbnail and do show one. Fixing this means a video decoding
dependency.

### Paste owns `PasteTextIntent`

Intercepting Ctrl+V in a `Focus.onKeyEvent` cannot work: the handler must answer
synchronously and every clipboard read is async. Overriding `PasteTextIntent`
instead also catches the context menu's *Paste* and Shift+Insert, and delegates
back to `EditableText` through `callingAction` when the clipboard holds no
attachment — so selection replacement and undo history stay the framework's job.
The cost is one clipboard round trip on every ordinary text paste.

Regression surface worth re-testing after touching `message_composer.dart`:
paste with a mid-word caret, paste over a selection, the context menu, and
Shift+Insert.

### Drafts are per room, text is not

Attachments staged in one room survive switching away and back, because
`AttachmentDrafts` is a non-autoDispose provider keyed by room id. Typed *text*
is still global — `MessageComposer` carries no `ValueKey(roomId)`, so its state
is reused across rooms. That predates this feature and is left alone
deliberately: adding the key would newly discard typed text on every switch.

### The `device_info_plus` override

`super_native_extensions` caps `device_info_plus` below 12.0.0 while
`livekit_client` requires `^12.3.0`. Without the override in `pubspec.yaml` pub
does **not** fail — it silently backtracks `super_*` to 0.1.x, a three-year-old
release with a different API. See the comment there for why overriding is safe.

If that ever stops being true, the three `attachment_*_source.dart` files are
the only ones that import an input package; `desktop_drop` + `pasteboard` is a
two-file swap. The cost of that route is no iOS support and no virtual files
(an attachment dragged straight out of Outlook or a zip viewer has no path).

## Custom themes

Settings → Appearance holds a **library** of themes. Each one is a name and a
value for every colour slot, and each can be applied, renamed, edited,
duplicated, exported to a file, or deleted. The three palettes the app ships
with are *seeded* into the library on first launch and are ordinary entries from
then on — there is no second, privileged kind of theme.

### The file format

An exported theme is UTF-8 JSON named `<theme name>.theme.json`. It ends in
`.json` because it *is* JSON: hand-editing one should get syntax highlighting
for free.

```json
{
  "format": "hardline.theme",
  "version": 1,
  "name": "Midnight",
  "colors": {
    "spaceRail": "#FF0A0A0B",
    "roomSidebar": "#FF101012",
    "timelineBackground": "#FF151517",
    "accent": "#FFFF7A18"
  },
  "avatarPalette": ["#FFFF7A18", "#FF4FC3F7"]
}
```

| Field | Meaning |
|---|---|
| `format` | Always `hardline.theme`. Files written by earlier builds say `matrix_client.theme` and are still accepted; anything else is refused. |
| `version` | Format version, currently `1`. A higher number is refused. |
| `name` | The theme's name. Trimmed, and capped at 60 characters. |
| `colors` | Slot name → `#AARRGGBB`. The slot names are the constants in `ColorSlot`; an export writes all of them, in that order. The three slots renamed in the redesign (`serverRail`, `channelSidebar`, `chatBackground`) are still read under their old names. |
| `avatarPalette` | The ramp used for users with no profile picture. Optional. |

Colours are written `#AARRGGBB` and read as either `#AARRGGBB` or `#RRGGBB`,
where the short form is taken as fully opaque. Alpha is always *written*,
because a handful of slots (`scrim`, `dropOverlay`, `voiceParticipantRow`) are
deliberately translucent and would import as solid blocks without it.

### Reading is deliberately forgiving

A file that declares itself a theme is read as far as it can be:

- **An unknown slot is ignored.** A theme written by a later version of the app
  can name slots this build has never heard of.
- **A missing slot is filled from the built-in dark palette.** A hand-written
  file listing four colours is a valid theme; the alternative is refusing
  somebody's work over a slot that was added after they saved it.
- **A single unparseable colour costs only that colour**, and is filled the same
  way.

What is *not* forgiven is identity: a file without the right `format`, without a
readable `version`, or without a `colors` object is refused outright, with a
sentence explaining which. Without that check any JSON object with a `colors`
key would silently become a theme.

### The file carries no id

Ids are local to an installation. Importing mints a fresh one, so an import can
never overwrite a theme already in the library — importing the same file twice
gives two entries, which is visible and undoable, rather than a silent
replacement. Name collisions are disambiguated (`Midnight (2)`) for the same
reason.

### What a theme is not

`tooltipDelay` is a setting, not a colour, and stays out of the file. The avatar
ramp *is* carried through export, import and duplication, but has no editor —
the colour grid renders `ColorSlot.all`, and the ramp is a list rather than a
slot. Anyone who wants to change it can edit an exported file and import it
back.

### Where the code lives

- `theme_entry.dart` — one theme, and the library's state. Storage shape only.
- `theme_file.dart` — the format above, as a pure codec. No `dart:io`, which is
  what lets every rule here be tested by handing a string to `decodeThemeFile`.
- `theme_file_io.dart` — the save/open dialogs and the disk. Isolates
  `file_selector` the way `attachment_picker_source.dart` does.
- `theme_library.dart` — the `Notifier` that owns the stored list.

Export is deliberately not a method on the library: it neither reads nor writes
the stored list, it serialises one entry the caller already has.

### The upgrade path from per-slot overrides

Before the library, colours were customised as a sparse patch over whichever
preset was selected — `AppThemeState.overrides`. Editing now happens *in* a
theme, so what is on screen is exactly what an export writes out, and nothing
writes to that field any more.

It is still read and still applied, so an installation that upgrades looks
identical to how it did. The appearance pane shows a one-time card offering to
save the patch as a theme of its own or to discard it, and after that it stays
empty forever. Removing the field outright would have silently reverted those
users' colours on first launch.

## Voice architecture

Notes that are expensive to rediscover.

### MatrixRTC, not the SDK's group calls

The `matrix` Dart SDK ships a VoIP layer, and it is **not usable here**. It
reads and writes `com.famedly.call.member`, a Famedly-only event type that no
Element client understands. Element Call uses `org.matrix.msc3401.call.member`.
The two never see each other.

So this app bypasses the SDK's VoIP layer entirely and speaks MatrixRTC
directly. See `matrix_rtc_membership.dart`.

Consequences worth knowing:

- **Leaving a call is an empty state event, not a redaction.** Most membership
  events in a synced room are `{}` tombstones from people who left. Anything
  that treats "has a state event" as "is in the call" will list everyone who was
  ever in one.
- The state key is `_{userId}_{deviceId}_m.call` (MSC3757 per-device keys).
- `importantStateEvents` in `matrix_bootstrap.dart` must list the membership
  type, or the SDK drops it for any room whose timeline was never opened — and
  the participant list is then permanently empty for exactly the rooms the user
  has not clicked into.

### The LiveKit room name is a hash

`lk-jwt-service` derives it as `SHA256(json([matrixRoomId, slotId]))`. The slot
is the literal string **`m.call#ROOM`** (`kMatrixRtcSlotId`), which is what the
legacy `/sfu/get` endpoint hardcodes. Sending the obvious-looking `m.call`
produces a different hash and lands you alone in an empty room — while the
token, the connection and the publication all report success. Symptom: nobody
hears anybody, and other clients show "waiting for media".

`/sfu/get` is therefore tried **before** `/get_token`, despite being deprecated:
it also assigns the plain-text identity `@user:server:DEVICEID` that Element
matches against Matrix memberships, where `/get_token` uses a hash.

### Device selection is not optional

`livekit_client` does not follow the operating system's default device. Its
`Hardware` singleton picks `devices.firstWhereOrNull(...)` — literally the first
enumerated entry, which on a machine with a virtual audio cable installed is
usually the cable.

Two separate mechanisms are needed, and using only one is a silent half-failure:

- **Output** — `Hardware.selectAudioOutput()`.
- **Input** — `AudioCaptureOptions(deviceId: …)` passed when the track is
  created. `Hardware.selectAudioInput()` alone is *not* enough: capture comes
  from `getUserMedia` constraints, so without a `deviceId` there is no
  constraint and the platform default wins.

### Switching the microphone mid-call is `setDeviceId`, not mute/unmute

`applyAudioDevices` used to swap devices by calling
`setMicrophoneEnabled(false)` then `setMicrophoneEnabled(true,
audioCaptureOptions: …)`. Reading what livekit_client does with that when a
publication already exists (`participant/local.dart`, `setSourceEnabled`) turns
up two problems rather than one:

- `false` is `publication.mute(stopOnMute: true)` — it **signals mute to the
  SFU**, so every remote peer watched us go muted and back for a change they
  should never have noticed.
- **`audioCaptureOptions` is ignored on that path.** It is read only for
  `stopAudioCaptureOnMute`; the unmute calls `restartTrack()` with the options
  the track already holds. So the `deviceId` constraint never arrived and the
  switch **did not actually work** — capture stayed on the old microphone.
  `Hardware.selectAudioInput` moved the native ADM's recording index, but
  libwebrtc applies that at `InitRecording`, not to a capture already running,
  so the settings dialog and the audio disagreed with nothing logging anything.

`LocalAudioTrack.setDeviceId()` is the API for this. It updates `currentOptions`
and restarts the track in place — `replaceTrack` on the existing sender, so the
publication, its sid and its frame cryptor all survive and nothing renegotiates.
The remaining gap is one `getUserMedia`, which is unavoidable: the device cannot
be changed under a live capture.

Two behaviours fall out of it for free, which is why there is no longer a
`republish` flag or any special-casing at the call sites:

- It **no-ops when the id is unchanged**, so changing the *output* device no
  longer disturbs the microphone.
- While **muted** it records the choice without opening the hardware, and
  `unmute()` restarts from it. Picking a microphone while muted now works.

For the same reason, `setMicMuted` passes no `audioCaptureOptions` — it would
be dead there too.

### A hard kill needs the server to withdraw the membership

Leaving a call is a client writing `{}` over its own membership. Every exit that
runs no Dart code — Task Manager, a crash, a power cut — therefore leaves us
advertised in a channel we are not in until `expires`, which is hours. The
`AppLifecycleListener` in `call_controller_provider.dart` covers only the
graceful close.

Two mechanisms, because neither is sufficient alone:

- **MSC4140 delayed events** (`delayed_leave.dart`). The `{}` write is scheduled
  on the homeserver at join time with a 20 s delay and its timer pushed back
  every 5 s. While we are alive it never fires; the moment we stop, it does.
  That inverts the failure mode — the *absence* of a client is now what removes
  us. Restarts are POSTs to the delayed-events endpoint, not room events, so
  unlike the membership itself they add nothing to the timeline.
- **A sweep** (`stale_membership_sweeper.dart`), for every homeserver that does
  not offer the above. It enforces one invariant off the sync tick: *if we are
  not in a call in room X, our device must not hold a live membership there.*

Three things are load-bearing:

- **Orphans are cancelled before a new withdrawal is scheduled.** A run that was
  killed leaves its withdrawal pending; rejoining inside the delay window would
  let it fire a few seconds later and clear the membership just published —
  vanishing from a channel while sitting in the call. (The SDK's own version of
  this loop in `famedly_call_extension.dart` never passes `from` when
  paginating, so do not copy it verbatim.)
- **Disarm happens before `_clearMembership`, not after.** Same reason in the
  other direction.
- **The sweep only touches our own user *and* our own device id**, and only
  while the controller is completely idle. `join()` publishes the membership
  before the status reaches `connected`, so a sweep in that window would clear
  a call being joined; another device of the same user may legitimately be in
  the call, which is what MSC3757 per-device state keys are for.

Synapse advertises `org.matrix.msc4140` **only when `max_event_delay_duration`
is set** in `homeserver.yaml` (e.g. `24h`). Unset, the delayed-leave half is
inert — it logs once and returns — and the sweep is what covers this.

### Audio state has one owner

Deafen, per-user local mute and per-user volume are three inputs to one track.
No code path touches a remote track directly; everything changes an input and
calls `_reapplyAudioState()`, which recomputes from all three. This is why
undeafening does not un-mute someone who was individually muted.

It re-runs on every `TrackSubscribedEvent`, which is what makes volumes survive
a peer rejoining — a new track arrives at gain 1.0 and LiveKit carries nothing
across.

Volume is stored **per device**, local mute **per person**: a gain calibrates
one microphone, while muting is a statement about a human.

### Media encryption

LiveKit encrypts frames; Matrix is only the transport that gets the keys to the
right devices. Every participant invents their own 16-byte key, sends it to the
others as an encrypted `io.element.call.encryption_keys` to-device event, and
feeds keys they receive into LiveKit's frame cryptor. See
`call_encryption_manager.dart`.

Two things in here were expensive to find, because **both fail silently**: keys
arrive, indices and identities are right, both ends report `AES-GCM`, and no log
anywhere says anything is wrong.

- **The derivation must be HKDF, not PBKDF2.** The 16 bytes exchanged are only
  key *material*; the AES key is derived from them. LiveKit's web SDK imports
  raw bytes as HKDF material (`createKeyMaterialFromBuffer`) and Element Call
  sets its keys from raw bytes, so it derives with HKDF — while the native
  default is PBKDF2. Same material, different key, nothing decodes.
  `BaseKeyProvider.create()` does not expose the setting at all, which is why
  `createMatrixRtcKeyProvider()` builds `KeyProviderOptions` by hand.
- **A rotated key must be pushed to the running sender.** `E2EEManager` reads
  the key index exactly once, in `_addRtpSender` when a track is published.
  Rotating afterwards stores and distributes the new key while the sender keeps
  encrypting with the old index. Receivers are unaffected — they read the index
  from each frame header — so the symptom is one-directional: you hear everyone,
  nobody hears you.

Everything else:

- Enabled **only when the Matrix room is encrypted**, because everyone else
  follows the same rule — encrypting unilaterally would make us undecodable.
- `keyRingSize` is 255, not the default 16: indices count modulo 256, so a small
  ring makes index 17 overwrite index 1 after enough rotations. (Element passes
  256 to the web SDK; the native implementation documents 1–255.)
- The key is stored under the **LiveKit identity**, while `member.id` in the
  event is our **membershipID**. Identical strings today, different concepts —
  keeping them apart is what stops a future identity change from breaking this
  silently.
- A new key is generated on join and whenever somebody leaves; a mid-call joiner
  is sent the *current* key instead of forcing a rotation. Element additionally
  rotates on join once a grace period has passed. The security-relevant half — a
  departing participant losing access to later media — is implemented, and since
  media is never recorded, a joiner receiving the current key gains nothing
  retroactively.
- Membership changes are coalesced for two seconds before being believed. A
  rejoin is a withdrawal immediately followed by a publish, and participants
  republish as an expiry heartbeat; reacting per event sees people "leave" in
  the gaps. Every spurious rotation costs the whole call five seconds of
  silence.
- The LiveKit identity and the MatrixRTC `memberId` are the same string
  (`@user:server:DEVICEID`), so a key arriving for a member id is handed to
  LiveKit unchanged. This is why the legacy token endpoint matters: its
  plain-text identity is what makes the two line up.
- A received key is only accepted if the claimed member id belongs to the actual
  sender. Without that check any room member could hand us a key attributed to
  someone else and have their stream decoded as that person.
- A new key is published ~5 s before it is used. Encrypting with a key still in
  flight produces a burst of undecodable frames for everyone.
- Keys are never sent to a device whose keys we do not have — such a recipient
  is skipped, not fallen back to plaintext.

### Power levels gate joining

Joining writes `org.matrix.msc3401.call.member`, so it needs permission for that
state event. A fresh Synapse room has `state_default: 50`, making calls
moderator-only until someone adds an `events` entry. `voice_joinability.dart`
classifies this up front so the UI can explain it, and lowering the level
happens only after an explicit confirmation — it is permanent, room-wide and
visible to everyone.

Note room version 12 gives creators implicit power with no entry in `users`.

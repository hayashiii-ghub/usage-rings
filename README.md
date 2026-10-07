# Usage Rings

Personal macOS widget for remaining Codex, Claude, Cursor, and Grok Bot usage.
Requires macOS 26+; Xcode is only needed to build from source. This is independent of Context.

## Install or update

Download the latest [DMG](https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/usage-rings-macos.dmg)
or browse [GitHub Releases](https://github.com/hayashiii-ghub/usage-rings/releases).
Requires **macOS 26+ and Apple silicon**; Xcode is not needed to use the download.

Open the DMG, quit any running Usage Rings, and drag the app to Applications.
When updating, replace the existing copy in its current location instead of
installing a second copy. Open the installed app, then right-click the desktop,
choose **Edit Widgets**, and add **Usage Rings → AI Usage**. Keep the app running;
it refreshes every five minutes and after waking from sleep. There is no automatic
updater. Add the app to Login Items if desired.

The app is **not notarized by Apple**. macOS may block the first launch. If you
trust the source, follow Apple's [per-app approval instructions](https://support.apple.com/102445)
under **System Settings → Privacy & Security → Open Anyway**. See
[DISTRIBUTION.md](DISTRIBUTION.md) for checksums, installation limits, and optional
Claude Code status-line setup. The download does not change that setup automatically.

To build and install from source instead, use `make install` with Xcode installed.
It installs to `~/Applications` and connects Claude Code's status line when no
custom command exists. Existing custom commands are preserved and must be composed
manually. Paid Apple Developer membership is not required.

## Distribution

`make package-unnotarized` produces the DMG, ZIP, build manifest, and checksums for
this release route. `make package-draft` creates a review ZIP. The optional
`make package` command requires Developer ID signing and notarization; those are
not part of the current release plan. See [DISTRIBUTION.md](DISTRIBUTION.md).

## Accounts

The app uses sign-ins already stored on this Mac. Monitoring starts on launch;
turn off **Show AI usage** to stop polling.

| Provider | Local sign-in | Ring |
| --- | --- | --- |
| Codex | `~/.codex/auth.json` | Lowest remaining main window |
| Cursor | Cursor desktop session | Reported monthly plan percentage |
| Claude | Claude Code status-line output (v2.1.251+, Pro/Max) | Lowest remaining 5-hour / weekly window |
| Grok Bot | Same Cursor desktop account used by Grok Bot | Weekly allowance |

Codex, Cursor, and Grok Bot use internal endpoints, so provider changes may require
updates. API-key billing accounts and pooled Grok Bot enterprise quotas are unsupported.
No token refresh or account changes are made.

Claude uses the official [status-line output](https://code.claude.com/docs/en/statusline#rate-limit-usage).
Use Claude Code once after connecting; usage appears after an API response. The helper
stores only the two main usage windows, receipt time, and hashed response markers under
`~/Library/Caches/Usage Rings/`. It does not store the session payload, conversation paths,
or workspace metadata. Usage Rings reads no Claude credentials or Keychain items and
makes no Claude API requests. Repeated status-line UI events do not refresh the age of
an old reading. Without new Claude Code activity, the ring becomes unavailable after
20 minutes or when a reported reset passes. App refresh reads the cache every five minutes;
use **Refresh** to pick it up immediately.

To disconnect only this integration while keeping other Claude settings:

```sh
python3 script/claude-statusline-setup.py --uninstall
```

Login credentials stay out of the repository, logs, and widget data. The host contacts
only the matching provider endpoints. The sandboxed widget reads sanitized values
from the loopback-only `127.0.0.1:52388/v1/usage` bridge, then caches them in its own
container. Other local processes can read those usage values; there is no LAN listener.

macOS controls widget updates. Missing/failed readings, values older than 20 minutes,
and passed reset times display **—** until a new reading arrives. Extra spending
allowances are not substituted for included quota percentages.

The small widget uses a 2 × 2 grid of rings without percentage labels; VoiceOver
still reads each provider's remaining percentage. Missing or expired readings
show a **—** badge on the small ring. The medium widget keeps percentages below
the rings.

## Security and data FAQ

### Does Usage Rings send data to its developer?

No. The app has no developer-operated collection server or analytics. It makes
authenticated HTTPS requests to the matching service to retrieve usage: Codex at
`chatgpt.com`, Cursor at `cursor.com`, and Grok Bot at `api2.cursor.sh` using the
Cursor session. These requests contain the credentials required by that service.
Redirects are rejected. Claude usage is read locally from official Claude Code
status-line output; Usage Rings makes no Claude API requests.

### Does it read my login details or conversations?

For Codex, the app reads the existing session from `~/.codex/auth.json`. For Cursor
and Grok Bot, it reads Cursor's local session database in read-only mode. These
credentials are used in memory for the matching service's request and are not
copied into the widget cache or logs. The app does not refresh tokens or change
your accounts. It does not read Claude credentials, Keychain items, or conversation
files. The optional Claude helper receives status-line input, but saves only the
two main usage windows, receipt time, and hashed response markers—not the full
input, conversation paths, or workspace metadata.

### What is saved, and who can see it?

The widget caches display data on this Mac: provider status, usage percentages,
reset times, and update times. Claude's helper saves its separate local cache
under `~/Library/Caches/Usage Rings/`. Cache files use owner-only permissions.
There is no usage-history database or cloud sync.

The app shares display data with the widget over `127.0.0.1:52388`, which is
accessible only on this Mac, not over the LAN. It does not expose credentials.
Other processes on the same Mac can read this bridge; its request header is not
authentication, and it is not a security boundary against other local apps.

### What happens when I turn off Show AI usage?

The app stops scheduled polling and wake refreshes, clears its current display
data, and asks macOS to refresh the widget. It does not delete your sign-ins or
guarantee that an already-started request stops immediately. The local bridge
remains running with empty data, and the widget may retain its cache until macOS
updates it. Turning this setting off does not disconnect the optional Claude
status-line helper; use the disconnect command above to stop that integration.

### Is this an official integration, and are the numbers always current?

Usage Rings is an independent project, not endorsed by the providers. Codex,
Cursor, and Grok Bot use internal endpoints whose compatibility or permitted use
may change; provider approval is not established. Claude uses documented
status-line output. The app normally refreshes every five minutes, and macOS
controls widget updates. Missing or failed readings, readings older than 20
minutes, and passed reset times show **—** instead of an invented percentage.

### Why does macOS show a warning when opening the download?

The current download is not notarized by Apple and is not distributed through the
App Store. Download from this repository's Releases page and check the published
checksums. Checksums help detect a mismatched download; they do not establish
Apple approval or prove the app is safe. If you trust the source, follow Apple's
per-app approval instructions linked above. Never disable Gatekeeper globally.

## Development

```sh
make check   # parser, credential, snapshot, and bridge tests
make build   # build and verify signed app + widget bundles
make run     # run from dist without installing
swift run WidgetPreview dist/widget-preview.png # synthetic small/medium, light/dark fixture sheet
swift run WidgetPreview dist/widget-comparison.png dist/widget-before.png # compare with a saved baseline
```

`WidgetPreview` renders the production SwiftUI rings without starting the app,
reading credentials, contacting providers, or changing installed widgets. It
covers normal, missing, expired, and high/exhausted usage. The sheet uses fixed
170 × 170 and 360 × 170 point canvases; it does not emulate WidgetKit's desktop
compositing or the system's widget update scheduling.

### Source layout

- `Sources/UsageRings`: app entry point, `Views`, `Stores`, `Services`, and window `Support`.
- `Sources/UsageCore/Models`: shared usage values and freshness rules.
- `Sources/UsageCore/Parsing`: provider responses and official Claude status-line input.
- `Sources/UsageCore/Persistence`: sanitized snapshot and Claude status-line caches.
- `Sources/UsageCore/Views`: shared ring composition and provider marks; SVG assets stay in `Resources`.
- `Sources/UsageRingsWidget/Timeline`: timeline entries, preview data, and expiry scheduling.
- `Sources/UsageRingsWidget/Views`: WidgetKit view configuration; the snapshot reader stays at the target root.
- `Tools/WidgetPreview`: offline visual fixture renderer, excluded from the installed app bundle.

The Grok Bot mark is a transparent monochrome character glyph sized to match the
other provider marks. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for sources.

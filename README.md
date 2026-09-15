# Usage Rings

Personal macOS widget for remaining Codex, Cursor, Claude Code, and Grok Bot usage.
Requires macOS 26+ and Xcode to build. This is independent of Context.

## Install or update

```sh
make install
```

The app installs into `~/Applications/Usage Rings.app` and opens its detail window.
Right-click the desktop, choose **Edit Widgets**, and add **Usage Rings → AI Usage**.
Keep the app running; it refreshes every five minutes and after waking from sleep.
The menu-bar icon opens details or quits the app. There is no automatic updater or
GitHub Release workflow. To start it after login, add Usage Rings to macOS Login Items.

## Accounts

The app uses sign-ins already stored on this Mac. Monitoring starts on launch;
turn off **Show AI usage** to stop polling.

| Provider | Local sign-in | Ring |
| --- | --- | --- |
| Codex | `~/.codex/auth.json` | Lowest remaining main window |
| Cursor | Cursor desktop session | Reported monthly plan percentage |
| Claude | Claude Code credentials file or existing Keychain item | Lowest remaining 5-hour / weekly window |
| Grok Bot | Same Cursor desktop account used by Grok Bot | Weekly allowance |

These are personal integrations using internal endpoints, so provider changes may
require updates. API-key billing accounts and pooled Grok Bot enterprise quotas are
not supported. Claude Code Keychain access is noninteractive; an unreadable or expired
session is shown as requiring sign-in. No token refresh or account changes are made.

Login credentials stay out of the repository, logs, and widget data. The host contacts
only the matching provider endpoints. The sandboxed widget reads sanitized values
from the loopback-only `127.0.0.1:52388/v1/usage` bridge, then caches them in its own
container. Other local processes can read those usage values; there is no LAN listener.

macOS controls widget updates. Missing/failed readings, values older than 20 minutes,
and passed reset times display **—** until a new reading arrives. Extra spending
allowances are not substituted for included quota percentages.

## Development

```sh
make check   # parser, credential, snapshot, and bridge tests
make build   # build and verify signed app + widget bundles
make run     # run from dist without installing
```

The Grok Bot mark is a transparent monochrome character glyph sized to match the
other provider marks. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for sources.

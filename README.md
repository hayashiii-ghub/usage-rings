# Usage Rings

Personal macOS widget for remaining Codex, Claude, Cursor, and Grok Bot usage.
Requires macOS 26+ and Xcode to build. This is independent of Context.

## Install or update

```sh
make install
```

The app installs into `~/Applications/Usage Rings.app` and opens its detail window.
Right-click the desktop, choose **Edit Widgets**, and add **Usage Rings → AI Usage**.
Keep the app running; it refreshes every five minutes and after waking from sleep.
The menu-bar icon opens details or quits the app.
Installation also connects Claude Code’s status line to the bundled helper; an existing
custom status line is preserved and must be composed manually before connecting. There is no automatic updater or
GitHub Release workflow. To start it after login, add Usage Rings to macOS Login Items.

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

## Development

```sh
make check   # parser, credential, snapshot, and bridge tests
make build   # build and verify signed app + widget bundles
make run     # run from dist without installing
```

The Grok Bot mark is a transparent monochrome character glyph sized to match the
other provider marks. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) for sources.

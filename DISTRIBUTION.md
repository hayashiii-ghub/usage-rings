# Distribution

Usage Rings requires macOS 26+. The current local build produces Apple silicon
(`arm64`) code; packaging reads all three binaries and labels the actual architecture.
Intel or universal support needs a separate build and device verification.

## Distribution without paid Apple Developer membership

The default installation route is to build the published source locally using
macOS 26+ and Xcode, following [Install or update](README.md#install-or-update).
Paid Apple Developer membership is not required. `make install` installs and
opens the app and connects Claude Code's status line when no custom command
exists; the README explains that behavior. To inspect a build first without
installing or connecting the helper, use `make check` followed by `make build`.

An unnotarized ZIP is a separate preview option. Developer ID signing and Apple
notarization are optional future distribution work, not remaining requirements
for the source installation route.

Use `make package-draft` to prepare this artifact. Keep the `draft-unnotarized`
filename and disclose its ad-hoc signing state; it has no Apple-verified developer
identity or notarization. GitHub draft status is separate from signing status:
the release stays unpublished until an explicit publishing decision.

Before publishing, verify a downloaded ZIP on another supported Mac, including
first launch and desktop widget registration. Updating an existing installation
on the development Mac does not establish that a fresh download works elsewhere.
Keep the current release a draft until those checks are complete.

Recipients should verify the checksum and extract the app as described below.
If macOS blocks opening it because the developer cannot be verified, Apple's
[instructions for opening an app from an unknown developer](https://support.apple.com/guide/mac-help/mh40616/mac)
describe the per-app **Open Anyway** option in **System Settings → Privacy &
Security**. The recipient should use that option only after deciding they trust
this source. It may not be available under managed-device policies, and it does
not guarantee the widget will register. Do not use it for a malware warning or
a failed integrity check; stop and investigate those failures. Do not disable
Gatekeeper globally or remove quarantine attributes. Building from reviewed
source is an alternative for users with the required local development tools.

## Prepare a review artifact

Start from a clean committed checkout and run the required checks before building:

```sh
make check
APP_VERSION=0.1.1 APP_BUILD=2 make build
make package-draft
```

`APP_VERSION` is three numeric components; `APP_BUILD` is an increasing integer
from 1 to 9999. Local `make build` keeps its previous defaults (0.1.0, build 1,
release, ad-hoc signing). Set `SOURCE_REVISION` only to the full checked-out HEAD
hash; it defaults to HEAD. Both the app and widget record version, build, source
commit, source cleanliness, and configuration before signing. Packaging rejects
dirty source metadata, debug builds, mismatched components, or broken signatures.

`dist/packages/` receives a ZIP, JSON manifest, and `.sha256` file. Their names
include version, build, source revision, architecture, and `draft-unnotarized`.
Only the app bundle goes into the ZIP; no settings, accounts, caches, or source
checkout are added. The ZIP is unpacked and verified before the files are emitted.
The manifest records the actual signing state of the app, widget, and helper.

These draft artifacts are initially for review. An ad-hoc signature provides bundle
integrity but no verified developer identity or notarization. A downloaded copy
may be rejected by Gatekeeper. Keep any initial GitHub Release a **draft** and
explicitly label its assets unnotarized. Do not present it as ready for public
installation or ask recipients to disable Gatekeeper or remove quarantine.

## Optional: prepare a notarized public artifact

This path requires an already installed **Developer ID Application** certificate
and private key, and already configured notarization access. Certificate issuance,
Developer Program enrollment, and credential setup are separate authorized steps.
No certificate or credentials are included in this repository.

Read the installed identity hashes with `security find-identity -p codesigning -v`.
Use the SHA-1 hash of the intended Developer ID Application identity:

```sh
APP_VERSION=0.1.1 APP_BUILD=3 CODE_SIGN_IDENTITY='<installed-identity-SHA1>' make build
ditto -c -k --sequesterRsrc --keepParent 'dist/Usage Rings.app' dist/notary-upload.zip
xcrun notarytool submit dist/notary-upload.zip --keychain-profile '<existing-profile>' --wait
```

The build signs the widget, helper, then app with the same identity, hardened
runtime, and secure timestamps. It preserves the widget's sandbox/network-client
entitlements and does not grant debugging or sandbox exceptions to the host.
It does not fall back to ad-hoc signing if Developer ID signing fails.

Continue only after `notarytool` reports **Accepted**. If it fails, inspect the
submission log with `xcrun notarytool log '<submission-id>' --keychain-profile
'<existing-profile>'`; do not ship that artifact. After acceptance:

```sh
xcrun stapler staple 'dist/Usage Rings.app'
make package
```

`make package` requires valid Developer ID signatures, one matching team across
all three components, hardened runtime, secure timestamps, a valid stapled
ticket, and a successful Gatekeeper assessment. It produces a new final ZIP and
checksum after stapling. The temporary upload ZIP is not the distributable ZIP.
Run the packaged copy on another supported Mac, including desktop WidgetKit
registration, provider refresh, and Claude helper integration, before publishing.
Public publishing requires explicit approval; there is no publishing automation.

See Apple's [Developer ID overview](https://developer.apple.com/developer-id/),
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow),
and [code signing guidance](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).

## Recipient installation of a notarized release

Download the final ZIP and its matching `.sha256` file from the same release. In
their directory, run `shasum -a 256 -c '<downloaded-file>.sha256'`. Extract the ZIP,
quit any running Usage Rings, and move `Usage Rings.app` into `~/Applications`.
Open the app, then add **Usage Rings → AI Usage** through **Edit Widgets** on the
desktop. Keep the host running so it refreshes usage. Add it to Login Items if desired.

Moving the app does not connect Claude Code's status line automatically. To opt
in, merge the following property into `~/.claude/settings.json` (or the configured
Claude config directory). Preserve all other settings. If a custom `statusLine`
already exists, compose its command with the helper instead of replacing it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"$HOME/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\""
  }
}
```

The quoted command handles the space in the app's name. Use Claude Code once;
the usage reading appears after an API response. See [README](README.md#accounts)
for provider availability, cache freshness, and privacy details.

To disconnect this manual setup, remove only the `statusLine` property added
above. If it was composed with a custom command, remove only the Usage Rings
helper invocation and keep the custom command. The source installer’s
`--uninstall` recognizes only the command that installer wrote; it does not
remove this manual `$HOME` form.

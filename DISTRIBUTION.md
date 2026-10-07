# Distribution

Usage Rings uses the same download flow as Context: a GitHub Release DMG, then
drag the app into Applications. The app is **not notarized by Apple**. Paid
Apple Developer membership is not part of this distribution plan.

## Install a release

Requires macOS 26+ and **Apple silicon (arm64)**. The current app does not support
Intel Macs. Xcode is needed only when building from source, not for the downloads.

1. Download [usage-rings-macos.dmg](https://github.com/hayashiii-ghub/usage-rings/releases/latest/download/usage-rings-macos.dmg)
   from [GitHub Releases](https://github.com/hayashiii-ghub/usage-rings/releases).
2. Open the DMG. Quit any running Usage Rings and drag `Usage Rings.app` into
   Applications. When updating, replace the existing app in its current location
   so there is only one installed copy. If it is already in `~/Applications`,
   use that location rather than creating a second copy in `/Applications`.
3. Open the installed app. This is an ad-hoc signed, unnotarized app; macOS may
   block its first launch. If you trust the source, follow Apple's
   [per-app approval instructions](https://support.apple.com/102445) in
   **System Settings → Privacy & Security → Open Anyway**. Managed-device policy
   may prevent approval. Stop if macOS reports malware or an integrity failure.
4. Right-click the desktop, choose **Edit Widgets**, and add **Usage Rings → AI
   Usage**. Keep the host app running to refresh usage. Login Items are optional.

A ZIP is also available in the release. Extract it and follow steps 2–4. No
installer removes quarantine attributes or disables Gatekeeper. Claude Code
integration is optional; see below before changing an existing custom status line.

For verification, download `usage-rings-macos.zip`, `usage-rings-macos.dmg`,
`usage-rings-macos.json`, and `usage-rings-macos.sha256` from the same release,
then run `shasum -a 256 -c usage-rings-macos.sha256` in that directory. The JSON
records version, build, source commit, architecture, signing state and hashes.
Neither archive includes account credentials, settings, or usage caches.

The development Mac has confirmed the updated app and small widget. Fresh
installation, first-launch approval, and widget registration on a separate Mac
remain untested; publishing an unnotarized build does not imply those were tested.

## Build and package an unnotarized release

From a clean committed checkout with macOS 26+ and Xcode:

```sh
make check
APP_VERSION=0.1.1 APP_BUILD=3 make build
make package-unnotarized
```

This explicitly selects unnotarized distribution and creates a versioned folder
under `dist/packages/` with four assets:

- `usage-rings-macos.dmg`: compressed disk image with the app, Applications shortcut,
  and installation notes.
- `usage-rings-macos.zip`: the same app bundle.
- `usage-rings-macos.json`: build and signing metadata plus archive hashes.
- `usage-rings-macos.sha256`: checksums for the DMG, ZIP, and JSON.

Stable asset names support GitHub's `releases/latest/download` links; the local
versioned directory preserves earlier builds. Packaging rejects dirty-source or
debug builds, mismatched host/widget metadata, broken signatures, and invalid
entitlements. It extracts the ZIP and mounts the DMG read-only to recheck their
contents, then detaches it. It does not install or launch the app.

The mode never calls notarization or changes system security settings. Ad-hoc
signing checks bundle integrity but does not verify a developer's identity.
`make package-draft` remains available for a review-only ZIP. Release draft status
is independent of code signing: public publishing is an explicit release step.

`APP_VERSION` is three numeric components; `APP_BUILD` is an increasing integer
from 1 to 9999. Ordinary local builds retain their original defaults (0.1.0,
build 1). `SOURCE_REVISION` defaults to the full checked-out HEAD and cannot refer
to a different commit. The host and widget record the same version and build.

## Build from source instead

Clone the repository and run `make check`, then `make install`. This requires
Xcode but no paid Apple Developer membership. The source installer installs to
`~/Applications` and connects Claude Code's status line if no custom command
exists; custom commands are preserved. Use `make build` to inspect the bundle
without installing it or connecting the helper.

## Optional notarized build

This is not part of the current release plan. With an already installed Developer
ID Application certificate and configured notarization access, build using its
identity hash, submit to Apple, and staple an accepted ticket:

```sh
APP_VERSION=0.1.1 APP_BUILD=4 CODE_SIGN_IDENTITY='<installed-identity-SHA1>' make build
ditto -c -k --sequesterRsrc --keepParent 'dist/Usage Rings.app' dist/notary-upload.zip
xcrun notarytool submit dist/notary-upload.zip --keychain-profile '<existing-profile>' --wait
# Continue only after Apple reports Accepted:
xcrun stapler staple 'dist/Usage Rings.app'
make package
```

`make package` retains the stricter notarized mode: matching Developer ID teams,
hardened runtime, secure timestamps, a stapled ticket, and successful Gatekeeper
assessment. It does not silently fall back to the unnotarized mode. See Apple's
[Developer ID overview](https://developer.apple.com/developer-id/) and
[notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

## Optional Claude Code integration

Moving the app does not connect Claude Code's status line automatically. To opt
in, merge the following property into `~/.claude/settings.json` (or the configured
Claude config directory). Preserve all other settings. If a custom `statusLine`
already exists, compose its command with the helper instead of replacing it:

```json
{
  "statusLine": {
    "type": "command",
    "command": "\"/Applications/Usage Rings.app/Contents/Helpers/UsageRingsStatusline\""
  }
}
```

The quoted command handles the space in the app's name. If the app is installed
under `~/Applications`, replace `/Applications` with `$HOME/Applications` in that
command. Use Claude Code once;
the usage reading appears after an API response. See [README](README.md#accounts)
for provider availability, cache freshness, and privacy details.

To disconnect this manual setup, remove only the `statusLine` property added
above. If it was composed with a custom command, remove only the Usage Rings
helper invocation and keep the custom command. The source installer’s
`--uninstall` recognizes only the command that installer wrote; it does not
remove every manually written form.

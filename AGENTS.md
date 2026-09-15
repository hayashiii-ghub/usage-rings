# Usage Rings

Personal macOS usage monitor, extracted from Context. Keep the four providers and
WidgetKit extension independent of Context. Do not add releases or publishing workflows.

- `Sources/UsageRings`: menu-bar app, local session readers, polling and detail window.
- `Sources/UsageCore`: shared models, parsers, ring views and icons.
- `Sources/UsageRingsWidget`: WidgetKit extension and sanitized snapshot cache.
- Validation: `make check`, then `make build` for embedded bundle/signing checks.
- Installation/update for this Mac: `make install`.
- Never log, commit, or copy login credentials into the project or widget.

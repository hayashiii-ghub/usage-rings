#!/usr/bin/env python3
"""Archive only a verified app; public artifacts additionally need notarization."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parent.parent
METADATA_KEYS = (
    "CFBundleShortVersionString", "CFBundleVersion", "LSMinimumSystemVersion",
    "UsageRingsSourceRevision", "UsageRingsSourceDirty", "UsageRingsBuildConfiguration",
)


def run(*args):
    result = subprocess.run(args, capture_output=True, text=True)
    if result.returncode:
        raise ValueError(f"{args[0]} failed: {result.stderr.strip() or result.stdout.strip()}")
    return result


def read_metadata(app):
    with (app / "Contents/Info.plist").open("rb") as file:
        host = plistlib.load(file)
    widget = app / "Contents/PlugIns/UsageRingsWidget.appex"
    with (widget / "Contents/Info.plist").open("rb") as file:
        extension = plistlib.load(file)
    if host.get("CFBundleIdentifier") != "work.hayashigoto.UsageRings" or \
            extension.get("CFBundleIdentifier") != "work.hayashigoto.UsageRings.Widget":
        raise ValueError("Unexpected app or widget bundle identifier.")
    for key in METADATA_KEYS:
        if key not in host or host[key] != extension.get(key):
            raise ValueError(f"App/widget metadata missing or mismatched: {key}")
    if not re.fullmatch(r"(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})\.(?:0|[1-9][0-9]{0,3})",
                        str(host["CFBundleShortVersionString"])):
        raise ValueError("Invalid app version.")
    if not re.fullmatch(r"[1-9][0-9]{0,3}", str(host["CFBundleVersion"])):
        raise ValueError("Invalid build number.")
    if not re.fullmatch(r"[0-9a-f]{40}", str(host["UsageRingsSourceRevision"])):
        raise ValueError("Missing full source commit hash.")
    if host["UsageRingsSourceDirty"] is not False:
        raise ValueError("Packaging requires an app built from a clean source checkout.")
    if host["UsageRingsBuildConfiguration"] != "release":
        raise ValueError("Packaging requires CONFIGURATION=release.")
    if host["LSMinimumSystemVersion"] != "26.0":
        raise ValueError("Unexpected minimum macOS version.")
    return host, widget


def inspect_bundle(app, draft):
    metadata, widget = read_metadata(app)
    components = {
        "app": (app, app / "Contents/MacOS/UsageRings"),
        "widget": (widget, widget / "Contents/MacOS/UsageRingsWidget"),
        "statusline": (app / "Contents/Helpers/UsageRingsStatusline",) * 2,
    }
    for resource in ("LICENSE", "THIRD_PARTY_NOTICES.md", "AppIcon.icns"):
        if not (app / "Contents/Resources" / resource).is_file():
            raise ValueError(f"Missing bundled resource: {resource}")
    run("/usr/bin/codesign", "--verify", "--deep", "--strict", str(app))
    architecture = None
    signatures = {}
    teams = set()
    for name, (code, executable) in components.items():
        if not executable.is_file():
            raise ValueError(f"Missing executable: {name}")
        archs = sorted(run("/usr/bin/lipo", "-archs", str(executable)).stdout.split())
        if not archs or not set(archs) <= {"arm64", "x86_64"}:
            raise ValueError(f"Unsupported architecture: {name}")
        if architecture is not None and architecture != archs:
            raise ValueError("App, widget, and helper architectures differ.")
        architecture = archs
        run("/usr/bin/codesign", "--verify", "--strict", str(code))
        details = run("/usr/bin/codesign", "-d", "--verbose=4", str(code)).stderr
        developer_id = "Authority=Developer ID Application:" in details
        signature = {
            "type": "developer-id" if developer_id else "ad-hoc" if "Signature=adhoc" in details else "other",
            "hardened_runtime": "(runtime)" in details,
            "secure_timestamp": bool(re.search(r"^Timestamp=.+", details, re.MULTILINE)),
        }
        signatures[name] = signature
        entitlements_xml = run("/usr/bin/codesign", "-d", "--entitlements", "-", "--xml", str(code)).stdout.strip()
        entitlements = plistlib.loads(entitlements_xml.encode()) if entitlements_xml else {}
        if entitlements.get("com.apple.security.get-task-allow"):
            raise ValueError(f"Debugging entitlement present: {name}")
        if name == "widget" and (entitlements.get("com.apple.security.app-sandbox") is not True or
                                 entitlements.get("com.apple.security.network.client") is not True):
            raise ValueError("Widget sandbox/network entitlements are missing.")
        if not draft:
            if not developer_id or not signature["hardened_runtime"] or not signature["secure_timestamp"]:
                raise ValueError("Public packaging requires Developer ID, hardened runtime, and secure timestamps on all code. Use --draft for unnotarized review artifacts.")
            run("/usr/bin/codesign", "--verify", "--strict", "-R",
                "anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists", str(code))
            team = re.search(r"^TeamIdentifier=([A-Z0-9]+)$", details, re.MULTILINE)
            if not team:
                raise ValueError(f"Developer team identifier missing: {name}")
            teams.add(team.group(1))
    if not draft:
        if len(teams) != 1:
            raise ValueError("All code must be signed by the same developer team.")
        run("/usr/bin/xcrun", "stapler", "validate", str(app))
        run("/usr/sbin/spctl", "--assess", "--type", "execute", "--verbose=2", str(app))
    return {
        "version": metadata["CFBundleShortVersionString"],
        "build": metadata["CFBundleVersion"],
        "source_revision": metadata["UsageRingsSourceRevision"],
        "source_dirty": False,
        "configuration": "release",
        "minimum_macos": metadata["LSMinimumSystemVersion"],
        "architectures": architecture,
        "signatures": signatures,
        "notarization": "not-verified-draft" if draft else "stapled-and-gatekeeper-accepted",
        "distribution": "draft-unnotarized" if draft else "notarized",
    }


def package(app, output, draft):
    output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".package-", dir=output) as temporary:
        staging = Path(temporary)
        staged_app = staging / "Usage Rings.app"
        run("/usr/bin/ditto", str(app), str(staged_app))
        manifest = inspect_bundle(staged_app, draft)
        architecture = "universal" if len(manifest["architectures"]) == 2 else manifest["architectures"][0]
        name = (f"Usage-Rings-{manifest['version']}-build{manifest['build']}-"
                f"{manifest['source_revision'][:12]}-macOS-{architecture}-{manifest['distribution']}")
        files = [name + suffix for suffix in (".zip", ".json", ".sha256")]
        if any((output / file).exists() for file in files):
            raise ValueError("An artifact with this version/build/revision already exists; use a new build number or remove the old local artifact deliberately.")
        archive = staging / files[0]
        run("/usr/bin/ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staged_app), str(archive))
        extracted = staging / "roundtrip"
        run("/usr/bin/ditto", "-x", "-k", str(archive), str(extracted))
        if inspect_bundle(extracted / "Usage Rings.app", draft) != manifest:
            raise ValueError("Archive round-trip changed bundle metadata or signing state.")
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        manifest.update({"archive": files[0], "sha256": digest})
        (staging / files[1]).write_text(json.dumps(manifest, indent=2) + "\n")
        (staging / files[2]).write_text(f"{digest}  {files[0]}\n")
        for file in files:
            (staging / file).replace(output / file)
        return output / files[0]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--draft", action="store_true", help="Create an explicitly unnotarized review artifact; never publish as a notarized release.")
    args = parser.parse_args()
    try:
        archive = package(ROOT / "dist/Usage Rings.app", ROOT / "dist/packages", args.draft)
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        parser.exit(1, f"Packaging: {error}\n")
    print(archive)


if __name__ == "__main__":
    main()

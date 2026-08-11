#!/usr/bin/env python3
"""Capture the eight localized Google Play phone-screen states from an API 35 AVD."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import struct
import subprocess
import time

ANDROID_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = ANDROID_ROOT.parents[1]
PACKAGE = "com.healthmd.android"
ACTIVITY = "com.healthmd.presentation.MainActivity"
ROUTE_EXTRA = "com.healthmd.START_ROUTE"
CAPTURE_NAMES = (
    "1-core-export.png",
    "2-export-formats.png",
    "3-health-metrics.png",
    "4-private-by-design.png",
    "5-scheduled-exports.png",
    "6-file-preview.png",
    "7-home-screen-widgets.png",
    "8-direct-cli.png",
)
ANDROID_LANGUAGE_TAGS = {
    "ar": "ar",
    "bn-BD": "bn-BD",
    "de-DE": "de-DE",
    "es-ES": "es-ES",
    "fr-FR": "fr-FR",
    "hi-IN": "hi-IN",
    "ja-JP": "ja-JP",
    "kk": "kk-KZ",
    "nl-NL": "nl-NL",
    "pa": "pa-Guru-IN",
    "pt-BR": "pt-BR",
    "ro": "ro-RO",
    "ru-RU": "ru-RU",
    "uk": "uk-UA",
    "zh-CN": "zh-Hans-CN",
}


def arguments() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--serial", default=os.environ.get("ANDROID_SERIAL", "emulator-5554"))
    parser.add_argument("--locales", help="Comma-separated Play locales; defaults to every draft locale")
    parser.add_argument(
        "--output-root",
        type=Path,
        default=ANDROID_ROOT / "build" / "play-screenshot-captures",
    )
    parser.add_argument("--skip-system-locale", action="store_true", help="Avoid rebooting; useful for capture debugging")
    return parser.parse_args()


def run(command: list[str], *, check: bool = True, capture: bool = False) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        command,
        check=check,
        stdout=subprocess.PIPE if capture else subprocess.DEVNULL,
        stderr=subprocess.PIPE if capture else None,
    )


def adb_path() -> str:
    configured = os.environ.get("ANDROID_HOME") or os.environ.get("ANDROID_SDK_ROOT")
    candidates = [
        Path(configured) / "platform-tools" / "adb" if configured else None,
        Path.home() / "Library/Android/sdk/platform-tools/adb",
    ]
    for candidate in candidates:
        if candidate and candidate.is_file():
            return str(candidate)
    return "adb"


def wait_for_boot(adb: str, serial: str, timeout: int = 180) -> None:
    deadline = time.time() + timeout
    while time.time() < deadline:
        state = run([adb, "-s", serial, "get-state"], check=False, capture=True)
        booted = run(
            [adb, "-s", serial, "shell", "getprop", "sys.boot_completed"],
            check=False,
            capture=True,
        )
        if state.returncode == 0 and state.stdout.strip() == b"device" and booted.stdout.strip() == b"1":
            return
        time.sleep(2)
    raise RuntimeError(f"Timed out waiting for {serial} to boot")


def shell(adb: str, serial: str, *parts: str, check: bool = True) -> None:
    run([adb, "-s", serial, "shell", *parts], check=check)


def set_locale(adb: str, serial: str, locale: str, skip_system: bool) -> None:
    tag = ANDROID_LANGUAGE_TAGS[locale]
    if not skip_system:
        run([adb, "-s", serial, "root"], check=False)
        wait_for_boot(adb, serial, timeout=60)
        shell(adb, serial, "setprop", "persist.sys.locale", tag)
        shell(adb, serial, "settings", "put", "system", "system_locales", tag)
        run([adb, "-s", serial, "reboot"], check=False)
        wait_for_boot(adb, serial)
        time.sleep(3)
        applied_system_locale = run(
            [adb, "-s", serial, "shell", "getprop", "persist.sys.locale"],
            capture=True,
        ).stdout.decode("utf-8", errors="replace").strip()
        if applied_system_locale != tag:
            raise RuntimeError(f"Failed to apply system locale {tag}; found {applied_system_locale!r}")
        shell(adb, serial, "pm", "clear", "com.google.android.apps.nexuslauncher", check=False)
        time.sleep(3)
    for attempt in range(3):
        shell(
            adb,
            serial,
            "cmd",
            "locale",
            "set-app-locales",
            PACKAGE,
            "--user",
            "0",
            "--locales",
            tag,
        )
        time.sleep(2)
        configured = run(
            [adb, "-s", serial, "shell", "cmd", "locale", "get-app-locales", PACKAGE, "--user", "0"],
            capture=True,
        ).stdout.decode("utf-8", errors="replace")
        if tag in configured or tag.split("-")[0] in configured:
            break
    else:
        raise RuntimeError(f"Failed to apply app locale {tag}: {configured.strip()}")
    for namespace, key, value in (
        ("global", "window_animation_scale", "0"),
        ("global", "transition_animation_scale", "0"),
        ("global", "animator_duration_scale", "0"),
        ("system", "font_scale", "1.0"),
    ):
        shell(adb, serial, "settings", "put", namespace, key, value)


def launch(adb: str, serial: str, route: str, delay: float = 5.0) -> None:
    shell(adb, serial, "am", "force-stop", PACKAGE)
    shell(
        adb,
        serial,
        "am",
        "start",
        "-W",
        "-n",
        f"{PACKAGE}/{ACTIVITY}",
        "--es",
        ROUTE_EXTRA,
        route,
    )
    time.sleep(delay)


def screenshot(adb: str, serial: str, output: Path) -> None:
    result = run([adb, "-s", serial, "exec-out", "screencap", "-p"], capture=True)
    output.write_bytes(result.stdout)
    data = result.stdout
    if data[:8] != b"\x89PNG\r\n\x1a\n" or len(data) < 24:
        raise RuntimeError(f"Malformed screenshot: {output}")
    width, height = struct.unpack(">II", data[16:24])
    if (width, height) != (1080, 2340):
        raise RuntimeError(f"Unexpected screenshot dimensions {width}x{height}: {output}")


def capture_widget_picker(adb: str, serial: str, output: Path) -> None:
    shell(adb, serial, "input", "keyevent", "HOME")
    time.sleep(2)
    shell(adb, serial, "input", "swipe", "540", "900", "540", "900", "1200")
    time.sleep(2)
    shell(adb, serial, "input", "tap", "540", "590")
    time.sleep(3)
    shell(adb, serial, "input", "tap", "350", "500")
    shell(adb, serial, "input", "text", "Health")
    time.sleep(2)
    shell(adb, serial, "input", "keyevent", "BACK")
    time.sleep(1)
    shell(adb, serial, "input", "tap", "540", "700")
    time.sleep(4)
    screenshot(adb, serial, output)


def capture_locale(adb: str, serial: str, locale: str, output_root: Path, skip_system: bool) -> None:
    output = output_root / locale
    output.mkdir(parents=True, exist_ok=True)
    for existing in output.glob("*.png"):
        existing.unlink()

    print(f"Capturing {locale} ({ANDROID_LANGUAGE_TAGS[locale]})", flush=True)
    set_locale(adb, serial, locale, skip_system)

    launch(adb, serial, "export")
    screenshot(adb, serial, output / CAPTURE_NAMES[0])

    shell(adb, serial, "input", "swipe", "540", "1500", "540", "450", "600")
    time.sleep(1)
    shell(adb, serial, "input", "swipe", "540", "1500", "540", "700", "500")
    time.sleep(2)
    screenshot(adb, serial, output / CAPTURE_NAMES[1])

    launch(adb, serial, "metric_selection")
    screenshot(adb, serial, output / CAPTURE_NAMES[2])

    launch(adb, serial, "onboarding")
    screenshot(adb, serial, output / CAPTURE_NAMES[3])

    launch(adb, serial, "schedule")
    screenshot(adb, serial, output / CAPTURE_NAMES[4])

    launch(adb, serial, "export")
    preview_x = "780" if locale == "ar" else "300"
    shell(adb, serial, "input", "tap", preview_x, "1900")
    time.sleep(10)
    screenshot(adb, serial, output / CAPTURE_NAMES[5])

    capture_widget_picker(adb, serial, output / CAPTURE_NAMES[6])

    launch(adb, serial, "direct_cli")
    screenshot(adb, serial, output / CAPTURE_NAMES[7])

    found = sorted(path.name for path in output.glob("*.png"))
    if found != sorted(CAPTURE_NAMES):
        raise RuntimeError(f"Incomplete capture set for {locale}: {found}")


def main() -> None:
    args = arguments()
    manifest = json.loads((ANDROID_ROOT / "play-console/locales.json").read_text())
    draft_locales = [entry["playLocale"] for entry in manifest["locales"] if entry["status"] == "draft"]
    locales = args.locales.split(",") if args.locales else draft_locales
    unknown = sorted(set(locales) - set(ANDROID_LANGUAGE_TAGS))
    if unknown:
        raise SystemExit(f"Unsupported capture locales: {', '.join(unknown)}")

    adb = adb_path()
    wait_for_boot(adb, args.serial)
    for locale in locales:
        capture_locale(adb, args.serial, locale, args.output_root, args.skip_system_locale)

    capture_manifest = {
        "schemaVersion": 1,
        "device": {"serial": args.serial, "size": [1080, 2340], "api": 35},
        "locales": locales,
        "screens": list(CAPTURE_NAMES),
    }
    args.output_root.mkdir(parents=True, exist_ok=True)
    (args.output_root / "manifest.json").write_text(json.dumps(capture_manifest, indent=2) + "\n")
    print(f"Captured {len(locales) * len(CAPTURE_NAMES)} localized app screens in {args.output_root}")


if __name__ == "__main__":
    main()

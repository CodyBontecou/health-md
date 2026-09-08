#!/usr/bin/env python3
"""Generate an isolated, production-backed native component test project.

No source copies are maintained by hand. The status excerpt excludes only the
service-owning PartialExportNoticeToast. Its exact current-source span and digest
are recorded. All other production files are compiled directly. XcodeGen is a
local build prerequisite; generated project/results stay under Apple build/.
"""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess

APPLE = Path(__file__).resolve().parents[1]
ROOT = APPLE.parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument("output", type=Path)
args = parser.parse_args()
out = args.output.resolve()
if not out.is_relative_to(APPLE / "build"):
    parser.error("output must be inside this checkout's apps/apple/build")
out.mkdir(parents=True, exist_ok=True)
manifest = {"head": subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(), "sources": []}

def source(path):
    p = APPLE / path
    data = p.read_bytes()
    manifest["sources"].append({"path": path, "sha256": hashlib.sha256(data).hexdigest(), "mode": "direct"})
    return str(p)

status_path = "HealthMd/iOS/Components/StatusIndicator.swift"
status = (APPLE / status_path).read_text()
marker = "/// A warning toast that expands into partial-export details or Health permission guidance."
if status.count(marker) != 1:
    raise SystemExit("status extraction boundary changed; review it")
excerpt = status.split(marker)[0]
(out / "StatusComponents.generated.swift").write_text(excerpt)
manifest["sources"].append({"path": status_path, "sha256": hashlib.sha256(status.encode()).hexdigest(),
                           "mode": "prefix", "startLine": 1, "endLine": len(excerpt.splitlines()),
                           "excerptSha256": hashlib.sha256(excerpt.encode()).hexdigest()})
ids_path = "HealthMd/Shared/AccessibilityIdentifiers.swift"
ids = (APPLE / ids_path).read_text()
start = ids.index("    enum Status {")
end = ids.index("\n    }", start) + len("\n    }")
ids_excerpt = ids[start:end]
(out / "StatusIdentifiers.generated.swift").write_text("enum AccessibilityID {\n" + ids_excerpt + "\n}\n")
manifest["sources"].append({"path": ids_path, "sha256": hashlib.sha256(ids.encode()).hexdigest(),
                           "mode": "Status enum with namespace wrapper", "startLine": ids[:start].count("\n") + 1,
                           "endLine": ids[:end].count("\n") + 1, "excerptSha256": hashlib.sha256(ids_excerpt.encode()).hexdigest()})
shared = source("HealthMd/Shared/Theme/DesignSystem.swift")
tests = source("HealthMdTests/Views/A11yFoundationTests.swift")
helper = source("HealthMdTests/Support/A11yHosting.swift")
fonts = [source(str(p.relative_to(APPLE))) for p in sorted((APPLE / "HealthMd/Shared/Theme/Fonts").glob("*.ttf"))]
base = {"CODE_SIGNING_ALLOWED": "NO", "CODE_SIGNING_REQUIRED": "NO", "CODE_SIGN_IDENTITY": "", "DEVELOPMENT_TEAM": "", "SWIFT_VERSION": "5.0", "GENERATE_INFOPLIST_FILE": "YES"}
spec = {
    "name": "HealthMdA11y",
    "options": {"deploymentTarget": {"iOS": "17.0", "macOS": "14.0"}},
    "settings": {"base": base},
    "targets": {
        "HealthMd": {"type": "application", "platform": "iOS",
            "sources": [shared, source("HealthMd/iOS/Components/AnimatedButton.swift"),
                        str(out / "StatusIdentifiers.generated.swift"), str(out / "StatusComponents.generated.swift"),
                        source("AccessibilityTests/Host/A11ySyntheticApp.swift")] + fonts,
            "info": {"path": str(out / "Info.plist"), "properties": {
                "UIAppFonts": [Path(p).name for p in fonts], "UILaunchScreen": {},
                "UISupportedInterfaceOrientations": ["UIInterfaceOrientationPortrait", "UIInterfaceOrientationLandscapeLeft", "UIInterfaceOrientationLandscapeRight"]}},
            "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "org.healthmd.a11y.synthetic", "PRODUCT_MODULE_NAME": "HealthMd", "TARGETED_DEVICE_FAMILY": "1,2"}},
        "A11yTests": {"type": "bundle.unit-test", "platform": "iOS", "sources": [tests, helper], "dependencies": [{"target": "HealthMd"}], "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "org.healthmd.a11y.tests"}},
        "A11yUITests": {"type": "bundle.ui-testing", "platform": "iOS", "sources": [source("AccessibilityTests/UITests/A11yFoundationUITests.swift"), source("AccessibilityTests/UITests/A11yUITestSupport.swift")], "dependencies": [{"target": "HealthMd"}], "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "org.healthmd.a11y.uitests", "TEST_TARGET_NAME": "HealthMd"}},
        "HealthMdMac": {"type": "framework", "platform": "macOS", "sources": [shared], "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "org.healthmd.a11y.mac"}},
        "A11yMacTests": {"type": "bundle.unit-test", "platform": "macOS", "sources": [tests, helper], "dependencies": [{"target": "HealthMdMac"}], "settings": {"PRODUCT_BUNDLE_IDENTIFIER": "org.healthmd.a11y.mac.tests", "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "$(inherited) A11Y_ISOLATED_MAC"}}
    },
    "schemes": {
        "HealthMd-A11y-iOS": {"build": {"targets": {"HealthMd": "all"}}, "test": {"targets": ["A11yTests", "A11yUITests"]}},
        "HealthMd-A11y-macOS": {"build": {"targets": {"HealthMdMac": "all"}}, "test": {"targets": ["A11yMacTests"]}}
    }
}
(out / "project.json").write_text(json.dumps(spec, indent=2) + "\n")
(out / "source-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
subprocess.run(["xcodegen", "--spec", str(out / "project.json"), "--project", str(out)], check=True)
print(out / "HealthMdA11y.xcodeproj")

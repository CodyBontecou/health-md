#!/usr/bin/env python3
"""Run the existing Foundation-only workflow policy tests without building an app."""
from pathlib import Path
import subprocess
import tempfile


def main() -> None:
    apple = Path(__file__).resolve().parents[1]
    developer = Path(subprocess.check_output(["xcode-select", "-p"], text=True).strip())
    platform = developer / "Platforms/MacOSX.platform/Developer"
    frameworks = platform / "Library/Frameworks"
    libraries = platform / "usr/lib"
    private_frameworks = platform / "Library/PrivateFrameworks"
    with tempfile.TemporaryDirectory(prefix="healthmd-ci-policy-") as temporary:
        output = Path(temporary)
        entry = output / "main.swift"
        entry.write_text(
            "import XCTest\nimport Darwin\n"
            "let suite = CIQualityGateTests.defaultTestSuite\n"
            "suite.run()\n"
            "exit(suite.testRun!.totalFailureCount == 0 ? 0 : 1)\n"
        )
        command = [
            "xcrun", "swiftc", "-F", str(frameworks), "-I", str(libraries),
            "-L", str(libraries), "-module-cache-path", str(output / "module-cache"),
        ]
        for directory in (frameworks, libraries, private_frameworks):
            command += ["-Xlinker", "-rpath", "-Xlinker", str(directory)]
        command += [
            str(apple / "HealthMdTests/Utilities/CIQualityGateTests.swift"),
            str(entry), "-o", str(output / "policy-tests"),
        ]
        subprocess.run(command, check=True)
        subprocess.run([str(output / "policy-tests")], check=True)


if __name__ == "__main__":
    main()

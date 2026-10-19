#!/usr/bin/env python3
"""Exercise real Gradle compilation caching without caching JVM test results.

Run explicitly after the pinned wrapper distribution has been installed, for
example with ``./gradlew --version``. The fixture uses Gradle's bundled JUnit 4
and Hamcrest jars, so it needs neither Android tooling nor network access.
"""

import argparse
from contextlib import contextmanager
import errno
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import time
import xml.etree.ElementTree as ET


SCRIPT_DIR = Path(__file__).resolve().parent
GRADLE_VERSION = "8.11.1"


def _cleanup_note(error: BaseException, message: str) -> None:
    if hasattr(error, "add_note"):
        error.add_note(message)
    else:
        # The fixture also runs with older local Python versions.
        error.__notes__ = [*getattr(error, "__notes__", []), message]
        print(message, file=sys.stderr)


@contextmanager
def fixture_directory():
    root = Path(tempfile.mkdtemp(prefix="healthmd-ci-gradle-cache-"))
    primary_error = None
    try:
        yield root
    except BaseException as error:
        primary_error = error
        raise
    finally:
        # --stop can return before the daemon's final files reach this isolated
        # directory. Retry only that ENOTEMPTY race, including partial removals.
        deadline = time.monotonic() + 5.0
        attempts = 0
        while True:
            attempts += 1
            try:
                shutil.rmtree(root)
                break
            except OSError as error:
                remaining = deadline - time.monotonic()
                if error.errno == errno.ENOTEMPTY and remaining > 0:
                    time.sleep(min(0.1, remaining))
                    continue
                message = (
                    f"Fixture cleanup failed for {root} after "
                    f"{attempts} attempts: {error}"
                )
                if primary_error is not None:
                    _cleanup_note(primary_error, message)
                    break
                _cleanup_note(error, message)
                raise


def stop_fixture_daemon(gradle: Path, environment: dict) -> None:
    primary_error = sys.exc_info()[1]
    try:
        result = subprocess.run(
            [str(gradle), "--stop"], env=environment, text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30,
            check=False,
        )
        if result.returncode:
            raise RuntimeError(
                f"Failed to stop the fixture's isolated Gradle daemon "
                f"(exit {result.returncode}):\n{result.stdout}"
            )
        # A successful stop request can precede the daemon's final registry write.
        # Keep the owned home alive until its writers exit; fixture_directory also
        # retains main's bounded ENOTEMPTY retry and primary-error preservation.
        await_daemon_shutdown(Path(environment["GRADLE_USER_HOME"]))
    except (OSError, RuntimeError, subprocess.SubprocessError) as error:
        if primary_error is None:
            raise
        _cleanup_note(primary_error, f"Fixture daemon cleanup also failed: {error}")


def installed_gradle() -> Path:
    gradle_home = Path(os.environ.get("GRADLE_USER_HOME", Path.home() / ".gradle"))
    distributions = sorted(
        (gradle_home / "wrapper" / "dists" / f"gradle-{GRADLE_VERSION}-bin").glob(
            f"*/gradle-{GRADLE_VERSION}/bin/gradle"
        )
    )
    if not distributions:
        raise SystemExit(
            f"Install the pinned Gradle {GRADLE_VERSION} wrapper first with "
            "./gradlew --version, or pass --gradle /path/to/gradle."
        )
    return distributions[0]


def write_fixture(project: Path) -> None:
    (project / "src/main/java/fixture").mkdir(parents=True)
    (project / "src/test/java/fixture").mkdir(parents=True)
    (project / "settings.gradle").write_text(
        "rootProject.name = 'ci-gradle-cache-fixture'\n"
        "buildCache { local { directory = file('../build-cache') } }\n"
    )
    (project / "build.gradle").write_text(
        """plugins { id 'java' }
dependencies {
    testImplementation files(
        new File(gradle.gradleHomeDir, 'lib/junit-4.13.2.jar'),
        new File(gradle.gradleHomeDir, 'lib/hamcrest-core-1.3.jar')
    )
}
test {
    systemProperty 'fixture.contract', file('external-contract.txt').absolutePath
    systemProperty 'fixture.executions', file('executions.txt').absolutePath
    testLogging { events 'passed', 'failed' }
}
"""
    )
    (project / "src/main/java/fixture/Contract.java").write_text(
        'package fixture; public class Contract { public static String expected() { return "valid"; } }\n'
    )
    (project / "src/test/java/fixture/ContractTest.java").write_text(
        """package fixture;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.StandardOpenOption;
import org.junit.Test;
import static org.junit.Assert.assertEquals;

public class ContractTest {
    @Test public void readsCurrentExternalContract() throws Exception {
        Files.writeString(Path.of(System.getProperty("fixture.executions")), "executed\\n",
            StandardOpenOption.CREATE, StandardOpenOption.APPEND);
        assertEquals(Contract.expected(),
            Files.readString(Path.of(System.getProperty("fixture.contract"))).trim());
    }
}
"""
    )
    (project / "external-contract.txt").write_text("valid\n")


def await_daemon_shutdown(directory: Path, timeout: float = 30) -> None:
    """Wait for this temporary home's writers, not just Gradle's stop request."""
    pending = {int(log.stem.split("-")[1].split(".")[0])
               for log in directory.rglob("daemon-*.out.log")}
    deadline = time.monotonic() + timeout
    while pending:
        for pid in tuple(pending):
            status = subprocess.run(["ps", "-p", str(pid), "-o", "stat="],
                                    text=True, capture_output=True, check=False)
            # An exited process awaiting reaping cannot write the registry either.
            if status.returncode == 1 or status.stdout.strip().startswith("Z"):
                pending.remove(pid)
            elif status.returncode != 0:
                raise RuntimeError(f"Could not check fixture daemon {pid}: {status.stderr}")
        if pending:
            if time.monotonic() >= deadline:
                raise RuntimeError(f"Fixture Gradle daemons did not stop: {sorted(pending)}")
            time.sleep(.05)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--gradle", type=Path, help="Installed Gradle 8.11.1 executable")
    parser.add_argument("--receipt", type=Path, help="Retain compact results as JSON")
    args = parser.parse_args()
    gradle = (args.gradle or installed_gradle()).resolve()
    init_script = SCRIPT_DIR / "ci-gradle.init.gradle"
    receipt = {"gradle": str(gradle), "init_script": str(init_script), "runs": []}

    with fixture_directory() as root:
        project = root / "project"
        write_fixture(project)
        environment = dict(os.environ, GRADLE_USER_HOME=str(root / "gradle-home"))
        common = [str(gradle), "--project-dir", str(project), "--offline", "--build-cache",
                  "--console=plain", "--max-workers=2", "--daemon"]

        def executions() -> int:
            marker = project / "executions.txt"
            return len(marker.read_text().splitlines()) if marker.exists() else 0

        def report() -> dict:
            results = list((project / "build/test-results/test").glob("TEST-*.xml"))
            assert len(results) == 1, f"Expected one real JUnit XML report: {results}"
            suite = ET.parse(results[0]).getroot()
            return {field: int(suite.attrib[field]) for field in ("tests", "failures", "errors", "skipped")}

        def run(name: str, *, protected: bool, failing: bool = False) -> str:
            command = common + (["--init-script", str(init_script)] if protected else []) + ["test"]
            started = time.monotonic()
            result = subprocess.run(command, env=environment, text=True, stdout=subprocess.PIPE,
                                    stderr=subprocess.STDOUT, check=False)
            elapsed = round(time.monotonic() - started, 3)
            if (result.returncode != 0) != failing:
                raise AssertionError(f"Unexpected Gradle exit for {name}:\n{result.stdout}")
            summary = {"name": name, "seconds": elapsed, "exit_code": result.returncode,
                       "executions": executions(), "junit": report(),
                       "tasks": [line for line in result.stdout.splitlines()
                                 if line.startswith("> Task :compileJava") or line.startswith("> Task :test")]}
            receipt["runs"].append(summary)
            print(json.dumps(summary), flush=True)
            return result.stdout

        def discard_outputs() -> None:
            shutil.rmtree(project / "build")

        try:
            # Negative control: an undeclared repository input can pass from a stale
            # cached test result, then remain UP-TO-DATE after that input changes.
            run("unprotected-first", protected=False)
            assert executions() == 1
            discard_outputs()
            cached = run("unprotected-cache-restore", protected=False)
            assert "> Task :compileJava FROM-CACHE" in cached
            assert "> Task :test FROM-CACHE" in cached
            assert executions() == 1
            (project / "external-contract.txt").write_text("invalid\n")
            stale = run("unprotected-external-change", protected=False)
            assert "> Task :test UP-TO-DATE" in stale
            assert executions() == 1

            # The real init script must reuse compilation while running the same
            # JUnit case after cache restore, on an identical invocation, and after
            # a previously undeclared external input changes.
            (project / "external-contract.txt").write_text("valid\n")
            discard_outputs()
            cached = run("protected-cache-restore", protected=True)
            assert "> Task :compileJava FROM-CACHE" in cached
            assert "> Task :test FROM-CACHE" not in cached
            assert executions() == 2
            discard_outputs()
            cached = run("protected-second-cache-restore", protected=True)
            assert "> Task :compileJava FROM-CACHE" in cached
            assert "> Task :test FROM-CACHE" not in cached
            assert executions() == 3
            run("protected-identical-rerun", protected=True)
            assert executions() == 4
            (project / "external-contract.txt").write_text("invalid\n")
            run("protected-external-change", protected=True, failing=True)
            assert executions() == 5
            assert report() == {"tests": 1, "failures": 1, "errors": 0, "skipped": 0}
            receipt["conclusion"] = "success"
        finally:
            # Only this fixture's daemon and temporary build/cache paths are owned
            # here; never stop app builds or remove shared Gradle caches.
            stop_fixture_daemon(gradle, environment)

    receipt["temporary_resources_removed"] = True
    if args.receipt:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n")
    print("Gradle cache fixture passed: compilation restored; JVM tests always executed.")


if __name__ == "__main__":
    main()

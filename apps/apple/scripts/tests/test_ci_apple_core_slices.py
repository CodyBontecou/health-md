"""Exercise the production slice/assembly entry points with SDK-free tool stubs."""
from __future__ import annotations
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import ci_apple_core_slices as slices

SCRIPT = slices.REPO / "packages/healthmd-core-rust/scripts/build-apple-xcframework.sh"
SHA = "a" * 40
DIGEST = "b" * 64
TOOLCHAIN = "c" * 64


class SliceReceiptTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        for target in slices.TARGETS:
            path = self.root / (target + ".a")
            path.write_bytes(b"!<arch>\nsynthetic static archive " + target.encode())
            self.receipt(target)

    def receipt(self, target_name, **updates):
        value = dict(target=target_name, source_sha=SHA, source_digest=DIGEST, toolchain=TOOLCHAIN,
                     archive_sha256=slices.qualify(self.root / (target_name + ".a")))
        value.update(updates)
        (self.root / (target_name + ".json")).write_text(json.dumps(value))

    def test_every_required_architecture_is_verified(self):
        slices.verify(self.root, SHA, DIGEST, TOOLCHAIN)
        self.assertEqual(len(slices.TARGETS), 5)

    def test_archive_header_without_any_members_is_not_a_native_slice(self):
        empty = self.root / "empty.a"
        empty.write_bytes(b"!<arch>\n")
        with self.assertRaises(ValueError): slices.qualify(empty)

    def test_missing_corrupt_extra_or_wrong_source_slice_fails(self):
        target = slices.TARGETS[0]
        for field, bad in [("source_sha", "d" * 40), ("source_digest", "e" * 64),
                           ("toolchain", "f" * 64), ("target", slices.TARGETS[1]),
                           ("archive_sha256", "0" * 64)]:
            with self.subTest(field=field):
                self.receipt(target, **{field: bad})
                with self.assertRaises(ValueError): slices.verify(self.root, SHA, DIGEST, TOOLCHAIN)
                self.receipt(target)
        archive = self.root / (target + ".a")
        saved = archive.read_bytes()
        archive.unlink()
        with self.assertRaises(ValueError): slices.verify(self.root, SHA, DIGEST, TOOLCHAIN)
        archive.write_bytes(b"not a native archive")
        with self.assertRaises(ValueError): slices.verify(self.root, SHA, DIGEST, TOOLCHAIN)
        archive.write_bytes(saved)
        (self.root / "unexpected.a").write_bytes(saved)
        with self.assertRaises(ValueError): slices.verify(self.root, SHA, DIGEST, TOOLCHAIN)


class SourceDigestTests(unittest.TestCase):
    def test_vendor_only_changes_invalidate_native_source_digest(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            workspace = root / "packages/healthmd-core-rust"
            scripts = workspace / "scripts"
            scripts.mkdir(parents=True)
            digest_script = scripts / "apple-source-digest.sh"
            digest_script.write_bytes((SCRIPT.parent / "apple-source-digest.sh").read_bytes())
            files = ["Cargo.toml", "Cargo.lock", "rust-toolchain.toml",
                     "crates/healthmd-core/lib.rs", "crates/healthmd-core-uniffi/lib.rs",
                     "crates/healthmd-protocol/lib.rs", "scripts/build-apple-xcframework.sh",
                     "scripts/normalize-apple-xcframework.py", "scripts/validate-apple-xcframework.sh",
                     "vendor/askama_derive/src/config.rs"]
            for name in files:
                path = workspace / name
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text("original source")
            bindings = root / "apps/apple/Packages/HealthMdCoreRust/Bindings"
            bindings.mkdir(parents=True)
            (bindings / "core.swift").write_text("bindings")
            def digest():
                return subprocess.check_output(["sh", str(digest_script)], text=True).strip()
            before = digest()
            (workspace / "vendor/askama_derive/src/config.rs").write_text("updated parser source")
            self.assertNotEqual(before, digest())

    def test_every_new_native_cache_hashes_vendored_build_sources(self):
        for name in ("apple-ci.yml", "apple-nightly.yml"):
            workflow = (slices.REPO / ".github/workflows" / name).read_text()
            keys = [line for line in workflow.splitlines()
                    if "hashFiles(" in line and "apple-" in line]
            self.assertTrue(keys, name)
            for key in keys:
                with self.subTest(workflow=name, key=key):
                    self.assertIn("'packages/healthmd-core-rust/vendor/**'", key)


class NativeBuildEntrypointTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.bin = self.root / "bin"
        self.bin.mkdir()
        self.calls = self.root / "calls.jsonl"
        body = '''#!/usr/bin/env python3
import json,os,sys
from pathlib import Path
name=Path(sys.argv[0]).name;args=sys.argv[1:]
with Path(os.environ['MOCK_CALLS']).open('a') as f:
    f.write(json.dumps(dict(name=name,args=args,env={k:os.environ.get(k) for k in ['IPHONEOS_DEPLOYMENT_TARGET','MACOSX_DEPLOYMENT_TARGET','RUSTFLAGS','CARGO_ENCODED_RUSTFLAGS','SOURCE_DATE_EPOCH','ZERO_AR_DATE']}))+'\\n')
if name=='uname': print('Darwin')
elif name=='rustup' and args[0]=='which': print(Path(os.environ['MOCK_BIN'])/'rustc')
elif name=='cargo':
    target=args[args.index('--target')+1]
    path=Path(os.environ['CARGO_TARGET_DIR'])/target/'release/libhealthmd_core_uniffi.a'
    path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(b'!<arch>\\n'+target.encode())
elif name=='xcrun':
    output=Path(args[args.index('-output')+1]);output.parent.mkdir(parents=True,exist_ok=True)
    inputs=args[args.index('-create')+1:args.index('-output')]
    output.write_bytes(b''.join(Path(p).read_bytes() for p in inputs))
elif name=='xcodebuild':
    output=Path(args[args.index('-output')+1]);output.mkdir(parents=True)
    (output/'Info.plist').write_text('synthetic SDK-free packaging output')
'''
        # Absolute interpreter prevents the Python-normalizer stub recursing.
        body = body.replace("#!/usr/bin/env python3", "#!" + sys.executable, 1)
        for name in ("uname", "rustup", "cargo", "xcrun", "xcodebuild", "python3"):
            path = self.bin / name
            path.write_text(body)
            path.chmod(0o755)
        self.environment = dict(os.environ, PATH=f"{self.bin}:{os.environ['PATH']}",
                                MOCK_CALLS=str(self.calls), MOCK_BIN=str(self.bin),
                                CARGO_TARGET_DIR=str(self.root / "target"),
                                RUSTFLAGS="must-not-leak", CARGO_ENCODED_RUSTFLAGS="must-not-leak")

    def run_script(self, *args):
        return subprocess.run(["sh", str(SCRIPT), *map(str, args)], env=self.environment,
                              capture_output=True, text=True)

    def recorded(self, name):
        return [v for line in self.calls.read_text().splitlines()
                if (v := json.loads(line))["name"] == name]

    def test_slice_uses_same_pinned_release_build_and_only_requested_target(self):
        for target in slices.TARGETS:
            with self.subTest(target=target):
                result = self.run_script("--slice", target, self.root / (target + ".a"))
                self.assertEqual(result.returncode, 0, result.stderr)
                call = self.recorded("cargo")[-1]
                self.assertIn("--locked", call["args"])
                self.assertIn("--release", call["args"])
                self.assertIn("healthmd-core-uniffi", call["args"])
                self.assertEqual(call["args"][call["args"].index("--target")+1], target)
                self.assertIsNone(call["env"]["RUSTFLAGS"])
                self.assertIsNone(call["env"]["CARGO_ENCODED_RUSTFLAGS"])
                self.assertEqual(call["env"]["SOURCE_DATE_EPOCH"], "0")
                self.assertEqual(call["env"]["ZERO_AR_DATE"], "1")
                key = "MACOSX_DEPLOYMENT_TARGET" if target.endswith("darwin") else "IPHONEOS_DEPLOYMENT_TARGET"
                self.assertEqual(call["env"][key], "14.0" if key.startswith("MAC") else "17.0")
        self.assertEqual(len(self.recorded("cargo")), 5)

    def test_default_build_still_compiles_all_five_targets_and_packages_three_platforms(self):
        result = self.run_script(self.root / "complete.xcframework")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual([c["args"][c["args"].index("--target")+1] for c in self.recorded("cargo")], list(slices.TARGETS))
        package = self.recorded("xcodebuild")[-1]["args"]
        self.assertEqual(package.count("-library"), 3)
        self.assertEqual(package.count("-headers"), 3)

    def test_assembly_reuses_every_supplied_architecture_without_another_cargo_build(self):
        inputs = self.root / "slices"
        inputs.mkdir()
        for target in slices.TARGETS: (inputs / (target + ".a")).write_bytes(b"!<arch>\n" + target.encode())
        result = self.run_script("--assemble", inputs, self.root / "assembled.xcframework")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.recorded("cargo"), [])
        self.assertEqual(self.recorded("rustup"), [])
        self.assertEqual(len(self.recorded("xcrun")), 2)
        (inputs / (slices.TARGETS[1] + ".a")).unlink()
        self.assertNotEqual(self.run_script("--assemble", inputs, self.root / "bad.xcframework").returncode, 0)

    def test_unknown_architecture_is_rejected_before_any_compilation(self):
        self.assertNotEqual(self.run_script("--slice", "unsupported", self.root / "bad.a").returncode, 0)


if __name__ == "__main__": unittest.main()

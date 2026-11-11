#!/usr/bin/env python3
"""Host-only production Drive merger qualification against a freshly built core dylib.

Set HEALTHMD_HOST_CORE_LIBRARY to the task-owned healthmd-core-uniffi dylib.
No HealthKit, app launch, OAuth, simulator or network access is used.
"""
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

APPLE = Path(__file__).resolve().parents[2]

MAIN = r'''
import Foundation
import HealthMdCoreRust
import CryptoKit

enum GoogleDriveDigest { static func sha256(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() } }
enum GoogleDriveErrorID { case remoteConflict, checksumMismatch }
struct GoogleDriveError: Error { init(_ id: GoogleDriveErrorID) {} }

func patch(morning: Bool, sections: Bool) throws -> String {
    var record: [String: Any] = ["schema": "healthmd.health_data", "type": "health-data",
        "schema_version": morning ? 11 : 8, "date": "2026-03-08", "activity": ["steps": morning ? 42 : 99]]
    var clock = ["calendar_timezone": "America/New_York", "timestamp_timezone": "UTC"]
    if morning {
        record["schema_profile"] = "apple-v11"
        clock.merge(["sleep_day_attribution": "morning_ends", "sleep_owner_day_rule": "session_end_date",
            "sleep_interval_clipping": "none"]) { _, new in new }
    }
    record["time_context"] = clock
    let json = String(decoding: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), as: UTF8.self)
    return try HealthMdCoreService().prepareScopedNote(profile: morning ? .appleHealthDataV11 : .appleHealthDataV8,
        recordJSON: json, bases: "---\nsteps: \(morning ? 42 : 99)\n---\n",
        markdown: sections ? "## Activity\nNew activity.\n" : "", selectedProperties: ["steps"], injectSections: sections)
}
func rejects(_ body: () throws -> Void) {
    do { try body(); fatalError("Unsafe merge accepted") } catch {}
}

@main struct Main {
    static func main() throws {
        let personal = "---\njournal: personal\n---\nPersonal introduction.\n\n## My thoughts\nKeep me.\n"
        for sections in [false, true] {
            let morning = try patch(morning: true, sections: sections)
            let policy = GoogleDriveDailyNotePolicy(recordProfile: "apple-v11", injectSections: sections, patch: morning)
            // Serialized private retry authority preserves the exact patch and section setting.
            let recovered = try JSONDecoder().decode(GoogleDriveDailyNotePolicy.self, from: JSONEncoder().encode(policy))
            precondition(recovered == policy)
            var corrupted = try JSONSerialization.jsonObject(with: JSONEncoder().encode(policy)) as! [String: Any]
            corrupted["patch"] = "changed capture"
            let changed = try JSONDecoder().decode(GoogleDriveDailyNotePolicy.self,
                from: JSONSerialization.data(withJSONObject: corrupted))
            rejects { _ = try changed.merge(existing: "") }
            let created = try GoogleDriveFinalByteMerger.merge(baseline: Data(personal.utf8), fragment: Data(morning.utf8),
                intent: .dailyNoteMerge, dailyNotePolicy: recovered)
            let text = String(decoding: created, as: UTF8.self)
            precondition(text.contains("journal: personal") && text.contains("Personal introduction.") && text.contains("Keep me."))
            precondition(text.contains("healthmd_daily_injection_v1"))
            if !sections { precondition(!text.contains("New activity.")) }
            let night = try patch(morning: false, sections: sections)
            let nightPolicy = GoogleDriveDailyNotePolicy(recordProfile: "apple-v8", injectSections: sections, patch: night)
            let updated = try GoogleDriveFinalByteMerger.merge(baseline: created,
                fragment: Data("---\nsteps: 99\n---\n".utf8), intent: .dailyNoteMerge, dailyNotePolicy: nightPolicy)
            let result = String(decoding: updated, as: UTF8.self)
            precondition(result.contains("steps: 99") && result.contains("healthmd_daily_injection_v1") && result.contains("Keep me."))
            let replay = try GoogleDriveFinalByteMerger.merge(baseline: updated, fragment: Data(night.utf8),
                intent: .dailyNoteMerge, dailyNotePolicy: nightPolicy)
            precondition(replay == updated)
            rejects { _ = try GoogleDriveFinalByteMerger.merge(baseline: created, fragment: Data(night.utf8), intent: .dailyNoteMerge) }
            rejects { _ = try GoogleDriveFinalByteMerger.merge(baseline: Data("---\nschema: healthmd.health_data\nschema_version: 8\n---\n".utf8),
                fragment: Data(morning.utf8), intent: .dailyNoteMerge, dailyNotePolicy: policy) }
            rejects { _ = try GoogleDriveFinalByteMerger.merge(baseline: created, fragment: Data(night.utf8),
                intent: .dailyNoteMerge, dailyNotePolicy: .init(recordProfile: "future", injectSections: sections, patch: night)) }
        }
        let bodyPatch = try patch(morning: true, sections: true)
        rejects { _ = try GoogleDriveFinalByteMerger.merge(baseline: Data(), fragment: Data(bodyPatch.utf8), intent: .dailyNoteMerge,
            dailyNotePolicy: .init(recordProfile: "apple-v11", injectSections: false, patch: bodyPatch)) }
        print("PASS: Morning generation, Night transition, frozen policy replay, personal content, unsafe legacy and whole-export rejection")
    }
}
'''

class DriveScopedNotesTests(unittest.TestCase):
    def test_production_merger_with_real_core(self):
        library = os.environ.get('HEALTHMD_HOST_CORE_LIBRARY')
        self.assertTrue(library and Path(library).is_file(), 'Set HEALTHMD_HOST_CORE_LIBRARY to a freshly built dylib')
        package = APPLE / 'Packages/HealthMdCoreRust'
        shared = APPLE / 'HealthMd/Shared'
        with tempfile.TemporaryDirectory(prefix='drive-scoped-host-') as tmp:
            tmp = Path(tmp)
            bindings = package / 'Bindings'
            sources = list((package / 'Sources/HealthMdCoreRust').rglob('*.swift'))
            subprocess.run(['swiftc', '-emit-library', '-emit-module', '-module-name', 'HealthMdCoreRust',
                '-module-cache-path', str(tmp / 'cache'), '-I', str(bindings), '-Xcc',
                '-fmodule-map-file=' + str(bindings / 'HealthmdCoreFFI.modulemap'),
                *map(str, sources), str(library), '-o', str(tmp / 'libHealthMdCoreRust.dylib'),
                '-emit-module-path', str(tmp / 'HealthMdCoreRust.swiftmodule')], check=True)
            models = (shared / 'GoogleDrive/GoogleDriveModels.swift').read_text()
            types = models[models.index('nonisolated enum GoogleDriveArtifactWriteIntent'):models.index('nonisolated struct GoogleDriveGeneratedArtifact:')]
            merger = (shared / 'GoogleDrive/GoogleDriveDestinationRunner.swift').read_text()
            merger = merger[merger.index('nonisolated enum GoogleDriveFinalByteMerger'):]
            main = tmp / 'main.swift'
            main.write_text(MAIN + '\n' + types + '\n' + merger)
            subprocess.run(['swiftc', '-parse-as-library', '-module-cache-path', str(tmp / 'cache'),
                '-I', str(tmp), '-I', str(bindings), '-Xcc', '-fmodule-map-file=' + str(bindings / 'HealthmdCoreFFI.modulemap'),
                '-L', str(tmp), '-lHealthMdCoreRust', '-Xlinker', '-rpath', '-Xlinker', str(tmp),
                str(shared / 'Export/MarkdownMerger.swift'), str(main), '-o', str(tmp / 'test')], check=True)
            subprocess.run([str(tmp / 'test')], check=True)

if __name__ == '__main__':
    unittest.main()

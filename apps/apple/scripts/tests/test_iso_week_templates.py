"""Compile production date resolver bodies on macOS without building/launching an app."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

APPLE = Path(__file__).resolve().parents[2]


def member(source, signature):
    start = source.index(signature)
    end = source.index('\n    }', start) + len('\n    }')
    return source[start:end].replace('private ', '', 1)


@unittest.skipUnless(shutil.which('swiftc'), 'Swift host compiler required')
class ISOWeekTemplateTests(unittest.TestCase):
    def test_live_and_preview_resolvers_at_iso_boundaries(self):
        models = APPLE / 'HealthMd/Shared/Models'
        advanced = (models / 'AdvancedExportSettings.swift').read_text()
        daily = (models / 'DailyNoteInjectionSettings.swift').read_text()
        modal = (APPLE / 'HealthMd/iOS/Components/ExportModal.swift').read_text()
        helper = daily[daily.index('enum ISOWeekDateTokens {'):]
        harness = 'import Foundation\n' + helper + '\n'
        harness += 'struct ExportResolver { var exportTimeZoneOverride: TimeZone?\n'
        harness += member(advanced, '    private func applyDatePlaceholders(') + '\n}\n'
        harness += 'struct DailyResolver { var filenamePattern: String\n'
        harness += member(daily, '    func formatFilename(') + '\n}\n'
        # Inject only the clock/settings boundary. Each preview body is production source.
        harness += '''struct AdvancedExportSettings { static let defaultFilenameFormat = "{date}" }
struct FilenamePreview { var tempFormat: String; var testDate: Date
'''
        harness += member(modal, '    private var previewFilename:').replace('let date = Date()', 'let date = testDate') + '\n}\n'
        harness += 'struct FolderPreview { var tempStructure: String; var tempOrganizeFormatsIntoFolders = false; var testDate: Date\n'
        harness += member(modal, '    private var previewPath:').replace('let date = Date()', 'let date = testDate') + '\n}\n'
        harness += r'''
let utc = TimeZone(secondsFromGMT: 0)!
NSTimeZone.default = utc
let parser = ISO8601DateFormatter()
for (day, folder) in [
    ("2026-11-01", "2026/Week 44"),
    ("2027-01-01", "2026/Week 53"),
    ("2027-01-04", "2027/Week 01"),
    ("2029-12-31", "2030/Week 01"),
] {
    let date = parser.date(from: day + "T12:00:00Z")!
    let template = "{weekYear}/Week {week}/{date}"
    let resolver = ExportResolver(exportTimeZoneOverride: utc)
    precondition(resolver.applyDatePlaceholders(to: template, for: date) == folder + "/" + day)
    precondition(DailyResolver(filenamePattern: template).formatFilename(for: date, timeZone: utc) == folder + "/" + day)
    precondition(FilenamePreview(tempFormat: template, testDate: date).previewFilename == folder + "/" + day + ".md")
    precondition(FolderPreview(tempStructure: ISOWeekDateTokens.folderTemplate, testDate: date).previewPath == folder + "/" + day + ".md")
    // Existing numeric tokens and unknown markers retain their exact output.
    let legacy = "{date}/{year}/{YR}/{month}/{day}/{quarter}/{custom}"
    let year = String(day.prefix(4))
    let month = String(day.dropFirst(5).prefix(2))
    let dayNumber = String(day.suffix(2))
    let quarter = (Int(month)! - 1) / 3 + 1
    let expected = "\(day)/\(year)/\(year.suffix(2))/\(month)/\(dayNumber)/Q\(quarter)/{custom}"
    precondition(resolver.applyDatePlaceholders(to: legacy, for: date) == expected)
    precondition(DailyResolver(filenamePattern: legacy).formatFilename(for: date, timeZone: utc) == expected)
}
let boundary = parser.date(from: "2027-01-04T00:30:00Z")!
let la = TimeZone(identifier: "America/Los_Angeles")!
precondition(ExportResolver(exportTimeZoneOverride: la).applyDatePlaceholders(to: "{weekYear}/Week {week}/{date}", for: boundary) == "2026/Week 53/2027-01-03")
precondition(DailyResolver(filenamePattern: "{weekYear}/Week {week}/{date}").formatFilename(for: boundary, timeZone: la) == "2026/Week 53/2027-01-03")
print("ISO week live/preview boundaries, owner timezone and legacy bytes passed")
'''
        with tempfile.TemporaryDirectory(prefix='healthmd-iso-week-') as directory:
            directory = Path(directory)
            source = directory / 'main.swift'
            source.write_text(harness)
            binary = directory / 'iso-week'
            compiled = subprocess.run(['swiftc', '-module-cache-path', str(directory / 'modules'), str(source), '-o', str(binary)], capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            result = subprocess.run([str(binary)], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

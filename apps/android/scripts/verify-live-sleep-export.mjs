import assert from 'node:assert/strict';
import {readFile, readdir, writeFile, rm} from 'node:fs/promises';
import {createRequire} from 'node:module';
import path from 'node:path';
import {pathToFileURL} from 'node:url';
import {execFileSync} from 'node:child_process';

const [captureArg, pluginArg, zone] = process.argv.slice(2);
const checkOnly = captureArg === '--check-reader';
assert.ok(pluginArg && (checkOnly || (captureArg && zone)), 'Expected capture, pinned plugin checkout and calendar timezone');
const plugin = path.resolve(pluginArg);
const pin = JSON.parse(await readFile(new URL('../../website/external-sources.json', import.meta.url), 'utf8'));
const revision = execFileSync('git', ['rev-parse', 'HEAD'], {cwd: plugin, encoding: 'utf8'}).trim();
assert.equal(revision, pin.obsidian_plugin.revision, 'Use the exact pinned reader');
assert.equal(execFileSync('git', ['status', '--porcelain'], {cwd: plugin, encoding: 'utf8'}).trim(), '', 'Use a clean reader checkout');
const require = createRequire(path.join(plugin, 'package.json'));
const {build} = require('esbuild');
if (checkOnly) process.exit(0);
const capture = path.resolve(captureArg);
const bundle = path.join(capture, '..', 'acceptance-reader.mjs');
try {
  await build({stdin: {contents: [
    'export {parseJSON} from "./src/parsers/json-parser.ts";',
    'export {parseCSV} from "./src/parsers/csv-parser.ts";',
    'export {parseMarkdown} from "./src/parsers/markdown-parser.ts";',
    'export {canonicalSourceInstant} from "./src/native-source-clock.ts";',
    'export {nativeSourceRecordsAgree} from "./src/native-detail-markdown.ts";',
  ].join('\n'), resolveDir: plugin, loader: 'ts'}, bundle: true, platform: 'node', format: 'esm', outfile: bundle});
  const reader = await import(pathToFileURL(bundle));
  const baseline = JSON.parse(await readFile(path.join(capture, 'sdk-baseline.json'), 'utf8'));
  assert.ok(Array.isArray(baseline) && baseline.length > 0);
  assert.ok(baseline.every(source => typeof source.nativeId === 'string' && source.nativeId.trim()
    && typeof source.ownerDate === 'string' && /^\d{4}-\d{2}-\d{2}$/.test(source.ownerDate)
    && ['startOffset', 'endOffset', 'title', 'notes'].every(key => source[key] === null || typeof source[key] === 'string')
    && typeof source.source === 'string'), 'Invalid SDK baseline');
  assert.equal(new Set(baseline.map(source => source.nativeId)).size, baseline.length, 'Duplicate SDK source identity');
  const byDay = Map.groupBy(baseline, source => source.ownerDate);
  const clock = value => {
    const instant = reader.canonicalSourceInstant(value);
    assert.notEqual(instant, null, 'Invalid exact source clock');
    return instant.toString();
  };
  const intervals = rows => rows.map(row => `${clock(row.startTimeISO)}/${clock(row.endTimeISO)}`).sort();
  const totalSeconds = rows => {
    const nanos = rows.reduce((sum, row) => {
      const duration = BigInt(clock(row.endTimeISO)) - BigInt(clock(row.startTimeISO));
      assert.ok(duration > 0n, 'Invalid SDK source interval');
      return sum + duration;
    }, 0n);
    return Number(nanos / 1_000_000_000n) + Number(nanos % 1_000_000_000n) / 1e9;
  };
  const files = [];
  async function visit(folder) {
    for (const item of await readdir(folder, {withFileTypes: true})) {
      const file = path.join(folder, item.name);
      if (item.isDirectory()) await visit(file);
      else if (file !== path.join(capture, 'sdk-baseline.json') && file !== path.join(capture, 'receipt.json')) files.push(file);
    }
  }
  await visit(capture);
  const sourceDays = new Map();
  for (const file of files.filter(file => file.endsWith('.json'))) {
    const day = reader.parseJSON(await readFile(file, 'utf8'));
    assert.ok(day, 'Invalid native JSON companion');
    const key = `${path.relative(capture, file).split(path.sep)[0]}/${day.date}`;
    assert.ok(!sourceDays.has(key), 'Duplicate JSON owner');
    sourceDays.set(key, day);
  }
  const seen = new Set(), evidence = [];
  for (const file of files) {
    const relative = path.relative(capture, file);
    const metadata = relative.split(path.sep)[0];
    assert.ok(['true', 'false'].includes(metadata));
    const format = file.endsWith('-bases.md') ? 'bases' : file.endsWith('.md') ? 'markdown' : file.endsWith('.csv') ? 'csv' : file.endsWith('.json') ? 'json' : null;
    assert.ok(format, 'Unknown artifact format');
    const text = await readFile(file, 'utf8');
    const parsed = format === 'json' ? reader.parseJSON(text) : format === 'csv' ? reader.parseCSV(text) : reader.parseMarkdown(text);
    if (Array.isArray(parsed)) assert.equal(parsed.length, 1);
    const day = Array.isArray(parsed) ? parsed[0] : parsed;
    assert.ok(day, `Pinned reader rejected ${relative}`);
    assert.equal(day.schemaProfile, 'android-sleep-v6');
    assert.equal(day.timeContext?.calendar_timezone, zone);
    assert.equal(day.timeContext?.sleep_day_attribution, 'morning_ends');
    assert.equal(day.timeContext?.sleep_owner_day_rule, 'session_end_date');
    assert.equal(day.timeContext?.sleep_interval_clipping, 'none');
    const expected = byDay.get(day.date);
    assert.ok(expected, 'An unrequested owner was exported');
    assert.equal(path.basename(file), `${day.date}${format === 'bases' ? '-bases.md' : format === 'markdown' ? '.md' : `.${format}`}`);
    const sessions = day.sleep?.sleepSessions ?? [];
    assert.deepEqual(intervals(sessions), intervals(expected), `${relative}: complete source intervals and multiplicity`);
    const ids = sessions.map(source => source.identity?.nativeId);
    assert.deepEqual([...ids].sort(), expected.map(source => source.nativeId).sort(), `${relative}: source IDs`);
    const native = sourceDays.get(`${metadata}/${day.date}`);
    assert.ok(native, 'Missing JSON owner');
    assert.ok(reader.nativeSourceRecordsAgree(sessions, native.sleep?.sleepSessions ?? []), `${relative}: full parent source facts`);
    assert.ok(reader.nativeSourceRecordsAgree(day.sleep?.sleepStages ?? [], native.sleep?.sleepStages ?? []), `${relative}: full stage source facts`);
    for (const session of sessions) {
      const source = expected.find(row => row.nativeId === session.identity?.nativeId);
      assert.ok(source);
      assert.equal(session.exactStartTime?.offset, source.startOffset, `${relative}: source start offset`);
      assert.equal(session.exactEndTime?.offset, source.endOffset, `${relative}: source end offset`);
      assert.equal(session.title ?? null, source.title, `${relative}: source title`);
      assert.equal(session.notes ?? null, source.notes, `${relative}: source notes`);
      assert.equal(session.source, source.source, `${relative}: source origin`);
    }
    // Metadata-off Markdown intentionally rounds its visible summary. Its complete
    // native records above remain exact; machine summaries and metadata stay precise.
    if (format !== 'markdown' || metadata === 'true') {
      const expectedSeconds = totalSeconds(expected);
      const value = day.sleep?.totalDuration;
      assert.equal(typeof value, 'number', `${relative}: missing totalDuration`);
      assert.ok(Math.abs(value - expectedSeconds) <= Math.max(1e-9, expectedSeconds * Number.EPSILON * 4),
        `${relative}: truncated additive totalDuration`);
      if (format === 'json') assert.equal(JSON.parse(text).sleep.inBedTime, value, `${relative}: native in-bed duration`);
    }
    const key = `${metadata}/${day.date}/${format}`;
    assert.ok(!seen.has(key), 'Duplicate format/owner'); seen.add(key);
    evidence.push({path: relative, owner: day.date, format, metadata: metadata === 'true', exactIntervals: true,
      sourceIdentityVerified: true, sourceFieldsVerified: true,
      preciseTotalVerified: format !== 'markdown' || metadata === 'true'});
  }
  assert.equal(seen.size, byDay.size * 8);
  for (const day of byDay.keys()) for (const metadata of ['true', 'false']) for (const format of ['json', 'csv', 'markdown', 'bases']) {
    assert.ok(seen.has(`${metadata}/${day}/${format}`), 'Missing owner/metadata/format');
  }
  await writeFile(path.join(capture, '..', 'consumer-verification.json'), JSON.stringify({reader: revision, artifacts: evidence,
    fullFeatureAcceptance: false, limitation: 'Synthetic controls and a provider probe do not qualify broader production/recovery/device/accessibility acceptance.'}, null, 2)+'\n');
} finally {
  await rm(bundle, {force: true});
}

import assert from 'node:assert/strict';
import test from 'node:test';
import { mkdtemp, readFile, writeFile, rm } from 'node:fs/promises';
import { spawnSync } from 'node:child_process';
import path from 'node:path';
import os from 'node:os';

// Executes the exact published script against the exact published XML excerpts
// and checks the printed output matches what the article shows.
const post = await readFile(new URL('../content/blog/apple-health-export-xml-workout-distance.md', import.meta.url), 'utf8');
const fence = lang => [...post.matchAll(new RegExp('```' + lang + '\\n([\\s\\S]*?)\\n```', 'g'))].map(m => m[1]);
const [code] = fence('python');
const [legacyXml, currentXml] = fence('xml');
const [legacyCsv, currentCsv] = fence('csv');
const HEADER = 'type,start,end,duration,duration_unit,distance,distance_unit,distance_km,distance_type,distance_from,activities,source';

test('article has one script, two XML shapes and two shown outputs', () => {
  assert.equal(fence('python').length, 1);
  assert.equal(fence('xml').length, 2);
  assert.equal(fence('csv').length, 2);
  assert.match(legacyXml, /totalDistance="5\.02" totalDistanceUnit="km"/);
  assert.doesNotMatch(legacyXml, /WorkoutStatistics/);
  assert.match(currentXml, /<WorkoutStatistics type="HKQuantityTypeIdentifierDistanceWalkingRunning"[^>]*sum="5\.02" unit="km"/);
  assert.doesNotMatch(currentXml, /totalDistance/);
});

test('the first 60 words name both places distance lives', () => {
  const body = post.split(/^---$/m)[2];
  const words = body.replace(/[*`<>]/g, ' ').split(/\s+/).filter(Boolean).slice(0, 60).join(' ');
  assert.match(words, /WorkoutStatistics/);
  assert.match(words, /totalDistance/);
});

async function runner(t) {
  const dir = await mkdtemp(path.join(os.tmpdir(), 'healthmd-workout-distance-'));
  t.after(() => rm(dir, { recursive: true, force: true }));
  const script = path.join(dir, 'workout_distance.py');
  await writeFile(script, code);
  return async (xml, name = 'export.xml') => {
    const file = path.join(dir, name);
    await writeFile(file, xml);
    return spawnSync('python3', ['-I', script, file], { encoding: 'utf8', timeout: 10000 });
  };
}

test('published script prints the published output for both shapes', async t => {
  const run = await runner(t);
  for (const [xml, expected] of [[legacyXml, legacyCsv], [currentXml, currentCsv]]) {
    const result = await run(xml);
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, expected + '\n');
  }
  const rows = currentCsv.split('\n');
  assert.equal(rows[0], HEADER);
  assert.match(rows[3], /^TraditionalStrengthTraining,[^,]*,[^,]*,40,min,,,,,,0,/, 'missing distance is blank, not 0');
});

const withProlog = (xml, prolog) => xml.replace('<HealthData', `${prolog}\n<HealthData`);

test('an inline DTD, even a malformed one, does not stop the parse', async t => {
  const run = await runner(t);
  const valid = '<!DOCTYPE HealthData [\n<!-- HealthKit Export Version: 17 -->\n<!ELEMENT HealthData ANY>\n<!ATTLIST HealthData\n  locale CDATA #REQUIRED\n>\n]>';
  const malformed = '<!DOCTYPE HealthData [\n<!ELEMENT HealthData ANY>\n<!ATTLIST RightEye\n  CDATA #IMPLIED\n>\n]>';
  for (const prolog of [valid, malformed]) {
    const result = await run(withProlog(currentXml, prolog));
    assert.equal(result.status, 0, result.stderr);
    assert.equal(result.stdout, currentCsv + '\n');
  }
});

test('a repeated startDate on WorkoutStatistics is repaired, not fatal', async t => {
  const run = await runner(t);
  const broken = currentXml.replace(/(<WorkoutStatistics type="[^"]*" startDate="[^"]*" )endDate=/g, '$1startDate=');
  assert.notEqual(broken, currentXml);
  const result = await run(broken);
  assert.equal(result.status, 0, result.stderr);
  assert.equal(result.stdout, currentCsv + '\n');
});

test('multi-activity workouts read workout-level totals and never guess between sports', async t => {
  const run = await runner(t);
  const stat = (type, sum, unit) => `<WorkoutStatistics type="HKQuantityTypeIdentifierDistance${type}" startDate="2026-04-05 08:00:00 -0700" endDate="2026-04-05 09:35:00 -0700" sum="${sum}" unit="${unit}"/>`;
  const activity = (n, inner) => `<WorkoutActivity uuid="00000000-0000-4000-8000-00000000000${n}" startDate="2026-04-05 08:00:00 -0700" endDate="2026-04-05 09:35:00 -0700">${inner}</WorkoutActivity>`;
  const workout = (type, inner) => `<Workout workoutActivityType="HKWorkoutActivityType${type}" duration="95" durationUnit="min" sourceName="Example Watch" startDate="2026-04-05 08:00:00 -0700" endDate="2026-04-05 09:35:00 -0700">${inner}</Workout>`;
  const xml = `<?xml version="1.0" encoding="UTF-8"?>\n<HealthData locale="en_US">\n${[
    workout('SwimBikeRun', stat('Swimming', 750, 'm') + stat('Cycling', 20, 'km') + activity(1, stat('Swimming', 750, 'm')) + activity(2, stat('Cycling', 20, 'km'))),
    workout('Running', stat('WalkingRunning', 3, 'mi') + stat('Cycling', 1, 'km') + activity(1, stat('WalkingRunning', 3, 'mi'))),
    workout('Swimming', activity(1, stat('Swimming', 500, 'm'))),
    workout('Rowing', stat('Rowing', 2000, 'furlong')),
  ].join('\n')}\n</HealthData>\n`;
  const result = await run(xml);
  assert.equal(result.status, 0, result.stderr);
  const rows = result.stdout.trim().split('\n').map(line => line.split(','));
  assert.deepEqual(rows[1].slice(5, 11), ['', '', '', 'Cycling+Swimming', 'ambiguous', '2']);
  assert.deepEqual(rows[2].slice(5, 11), ['3', 'mi', '4.828', 'WalkingRunning', 'WorkoutStatistics', '1']);
  assert.deepEqual(rows[3].slice(5, 11), ['', '', '', '', '', '1'], 'activity-level statistics are not promoted to totals');
  assert.deepEqual(rows[4].slice(5, 11), ['2000', 'furlong', '', 'Rowing', 'WorkoutStatistics', '0'], 'unknown units keep the value but no km');
});

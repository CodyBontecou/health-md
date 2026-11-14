import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { test } from 'node:test';
import { assessInvocation, invocationDecision } from '../verification-policy.mjs';

const assess = (command, extra = {}) => assessInvocation({ tool: 'bash', input: { command }, ...extra });

test('device QA and every Argent tool require explicit task authorization', () => {
  for (const command of [
    'make apple-ios',
    'make -C apps/apple test-platforms',
    'xcrun simctl boot ABC',
    './gradlew :app:connectedPlayDebugAndroidTest',
    './gradlew :app:pixel6Api35DebugAndroidTest',
    'open /Applications/Xcode.app/Contents/Developer/Applications/Simulator.app',
    'adb -s emulator-5554 shell input tap 20 20',
    'xcrun devicectl device install app --device ABC app.ipa',
  ]) {
    assert.ok(assess(command).optIn.length > 0, command);
  }
  assert.deepEqual(assessInvocation({ tool: 'mcp__argent__list_devices', input: {} }).optIn, ['Argent']);
});

test('inspection, build-only commands, and host tests are not mistaken for device execution', () => {
  for (const command of [
    'rg "xcrun simctl boot" docs', 'printf "%s\\n" "make apple-ios"',
    '# xcrun simctl boot ABC\nnode --test test.mjs',
    'make -n apple-ios', './gradlew --dry-run connectedDebugAndroidTest',
    'xcrun simctl list devices', 'adb -s emulator-5554 devices',
    'xcodebuild build-for-testing -destination "platform=iOS Simulator"',
    './gradlew :app:assemblePlayDebugAndroidTest',
    'emulator -list-avds',
    'xcodebuild test -destination "platform=macOS" -scheme HealthMd-Tests-macOS',
    'make test-testing-tools', 'node --test tests.mjs',
  ]) assert.deepEqual(assess(command).optIn, [], command);
});

test('common wrappers and compound/nested execution do not bypass opt-in', () => {
  for (const command of [
    'env FOO=bar /usr/bin/xcrun simctl boot ABC',
    'bash -c "make apple-ios"',
    '/usr/bin/time -l bash -lc "make apple-ios"',
    'if xcrun simctl boot ABC; then echo done; fi',
    'xcrun xctrace record --device ABC',
    'npx playwright test',
    'echo safe; xcrun simctl boot ABC',
    'printf "%s" "$(xcrun simctl boot ABC)"',
    'adb shell input text devices',
    'bash apps/android/scripts/run-accessibility-ui-tests.sh',
    'python3 apps/android/scripts/capture-localized-play-screenshots.py',
  ]) assert.ok(assess(command).optIn.length, command);
  const batch = { tool: 'multi_tool_use.parallel', input: { tool_uses: [{ recipient_name: 'functions.bash', parameters: { command: 'make apple-ios' } }] } };
  assert.ok(assessInvocation(batch).optIn.length);
});

test('selection requires a plan, broad checks warn rather than prohibiting legitimate escalation', () => {
  assert.match(invocationDecision({ tool: 'bash', input: { command: 'cargo test -p owner behavior --locked' } }).block, /plan/);
  for (const command of ['make test-all', 'make coverage', 'cargo test --workspace --all-features --locked', './gradlew test']) {
    const invocation = { tool: 'bash', input: { command } };
    assert.equal(invocationDecision(invocation, { reason: '' }).warnings.length, 1, command);
    assert.equal(invocationDecision(invocation, { reason: 'Affected contract consumers' }).warnings.length, 0, command);
    assert.equal(invocationDecision(invocation, { reason: '' }).block, undefined, command);
  }
  assert.match(invocationDecision({ tool: 'bash', input: { command: 'make apple-ios' } }, { reason: 'Contract regression' }).block, /authorization/);
});

test('declared npm script chains expose hidden QA while ordinary host checks stay allowed', t => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), 'healthmd-script-guard-'));
  t.after(() => fs.rmSync(root, { recursive: true, force: true }));
  fs.writeFileSync(path.join(root, 'package.json'), JSON.stringify({ scripts: {
    verify: 'npm run browser', browser: 'playwright test',
    test: 'vitest run', typecheck: 'tsc --noEmit',
  } }));
  assert.ok(assess('npm run verify', { cwd: root }).optIn.length);
  assert.deepEqual(assess('npm test && npm run typecheck', { cwd: root }).optIn, []);
});

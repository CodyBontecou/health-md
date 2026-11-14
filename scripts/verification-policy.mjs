// A workflow guard, not a shell sandbox. Inspect executable positions rather
// than mentions in grep, quoted documentation, or comments. Opaque scripts still
// need human review; keep known entry points covered by behavioral tests.
import path from 'node:path';
import fs from 'node:fs';

function shellCommands(source) {
  const commands = [];
  let words = [], word = '', quote = '', started = false;
  const finishWord = () => {
    if (started) words.push(word);
    word = ''; started = false;
  };
  const finishCommand = () => {
    finishWord();
    if (words.length) commands.push(words);
    words = [];
  };
  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (char === '\\' && quote !== "'") {
      if (source[i + 1] === '\n') { i++; continue; }
      word += source[++i] ?? ''; started = true;
    } else if (quote) {
      if (char === quote) quote = '';
      else word += char;
    } else if (char === '"' || char === "'") {
      quote = char; started = true;
    } else if (char === '#' && !started) {
      while (i < source.length && source[i] !== '\n') i++;
      finishCommand();
    } else if (';|&\n()'.includes(char)) {
      finishCommand();
    } else if (/\s/.test(char)) {
      finishWord();
    } else {
      word += char; started = true;
    }
  }
  finishCommand();
  return commands;
}

function executable(words) {
  const result = [...words];
  while (result.length) {
    const bin = path.basename(result[0]);
    if (/^[A-Za-z_][\w]*=/.test(result[0]) || ['command', 'exec', 'nohup', 'if', 'then', 'else', 'do', 'while', 'until', '!', '{'].includes(bin)) result.shift();
    else if (['time', 'timeout'].includes(bin)) {
      result.shift();
      while (result[0]?.startsWith('-')) {
        const flag = result.shift();
        if (['-o', '-f', '-k', '--kill-after', '--signal', '-s'].includes(flag)) result.shift();
      }
      if (bin === 'timeout') result.shift();
    } else if (bin === 'env' || bin === 'sudo') {
      result.shift();
      while (result[0]?.startsWith('-')) {
        const flag = result.shift();
        if (['-u', '--unset', '-C', '--chdir', '-S', '-p'].includes(flag)) result.shift();
      }
    } else break;
  }
  return result;
}

function expansions(source) {
  const bodies = [];
  let quote = '';
  for (let i = 0; i < source.length; i++) {
    const char = source[i];
    if (char === '\\' && quote !== "'") { i++; continue; }
    if (char === "'" && quote !== '"') { quote = quote ? '' : "'"; continue; }
    if (quote === "'") continue;
    if (char === '"') { quote = quote ? '' : '"'; continue; }
    if (char === '#' && !quote && (i === 0 || /\s/.test(source[i - 1]))) {
      while (i < source.length && source[i] !== '\n') i++;
      continue;
    }
    if (char === '$' && source[i + 1] === '(') {
      const start = i + 2;
      let depth = 1;
      i = start;
      while (i < source.length && depth) {
        if (source[i] === '(') depth++;
        if (source[i] === ')') depth--;
        if (depth) i++;
      }
      bodies.push(source.slice(start, i));
    } else if (char === '`') {
      const start = ++i;
      while (i < source.length && source[i] !== '`') i++;
      bodies.push(source.slice(start, i));
    }
  }
  return bodies;
}

export function assessInvocation({ tool, input = {}, namespace = '', cwd }, nesting = 0) {
  const optIn = new Set(), broad = new Set();
  let verification = false;
  const name = `${namespace}/${tool}`;
  if (/(?:^|[\W_])argent(?:[\W_]|$)/i.test(name)) optIn.add('Argent');
  if (tool === 'multi_tool_use.parallel' && Array.isArray(input.tool_uses) && nesting < 8) {
    for (const call of input.tool_uses) {
      const child = assessInvocation({ tool: call.recipient_name, input: call.parameters, cwd }, nesting + 1);
      verification ||= child.verification;
      child.optIn.forEach(item => optIn.add(item));
      child.broad.forEach(item => broad.add(item));
    }
  }
  const visitedScripts = new Set();
  const inspect = (source, depth = 0, directory = cwd) => {
    if (depth > 8) return;
    for (const body of expansions(source)) inspect(body, depth + 1, directory);
    for (const rawWords of shellCommands(source)) {
      const [program = '', ...args] = executable(rawWords);
      const bin = path.basename(program);
      const joined = args.join(' ');
      if (bin === 'cd' && directory && args[0]) { directory = path.resolve(directory, args[0]); continue; }
      const shellFlag = args.findIndex(arg => /^-[A-Za-z]*c[A-Za-z]*$/.test(arg) || arg === '--command');
      if (['sh', 'bash', 'zsh', 'fish'].includes(bin) && shellFlag >= 0) {
        inspect(args[shellFlag + 1] ?? '', depth + 1, directory);
        continue;
      }
      // Read-only inspection does not execute the examples it searches.
      if (['rg', 'grep', 'cat', 'sed', 'printf', 'echo', 'git', 'ls', 'find'].includes(bin)) continue;
      if (bin === 'make' || bin === 'gmake') {
        if (args.some(a => ['--dry-run', '--just-print', '--recon'].includes(a) || /^-[^-]*n/.test(a))) continue;
        if (args.some(a => /^(test(?:[-:]|$)|check(?:[-:]|$)|coverage$|ci(?:[-:]|$)|apple-ios$|apple-macos$)/.test(a))) verification = true;
        if (args.some(a => ['test-all', 'test-platforms', 'test-android-all', 'coverage', 'ci'].includes(a))) broad.add('Broad Make qualification');
        if (args.some(a => /^(apple-ios|test-ios|test-platforms|ci-ios|test-ui(?:-.+)?|ui-test(?:-.+)?)$/.test(a))) optIn.add('Simulator/native UI QA');
      }
      if (/^(cargo|rustup)$/.test(bin) && /\b(test|clippy|check|fmt)\b/.test(joined)) {
        verification = true;
        if (args.includes('--workspace') || args.includes('--all') || args.includes('msrv')) broad.add('Rust workspace/MSRV qualification');
      }
      if (bin === 'swift' && ['test', 'build'].includes(args[0])) verification = true;
      if (bin === 'xcodebuild') {
        if (args.some(a => ['test', 'test-without-building'].includes(a))) {
          verification = true;
          if (/iOS|watchOS|tvOS|visionOS|UITests/i.test(joined) || !/platform=macOS/.test(joined)) optIn.add('Simulator/device/native UI QA');
        }
        if (/-enableCodeCoverage(?:=|\s+)YES/.test(joined)) broad.add('Coverage qualification');
      }
      if (bin === 'gradlew' || bin === 'gradle') {
        if (args.includes('--dry-run') || args.includes('-m')) continue;
        if (args.some(a => /test|check|lint|detekt|ktlint/i.test(a) && !a.startsWith('--'))) verification = true;
        if (args.includes('test') || args.includes('check')) broad.add('All-variant Gradle qualification');
        if (args.some(arg => {
          const task = arg.split(':').at(-1);
          return /connected\w*(?:Test|Check)|managedDevice|device.*AndroidTest/i.test(task)
            || (/AndroidTest$/i.test(task) && !/^(assemble|compile|package|bundle|process|merge|generate|lint)/i.test(task));
        })) optIn.add('Android device/emulator QA');
      }
      if (bin === 'xcrun' && args[0] === 'simctl' && !['list', 'help'].includes(args[1])) optIn.add('iOS simulator workflow');
      if (bin === 'xcrun' && args[0] === 'devicectl' && !['list', 'help'].includes(args[1])) optIn.add('Physical device workflow');
      if (bin === 'adb') {
        const tail = [...args];
        while (tail[0]?.startsWith('-')) {
          const flag = tail.shift();
          if (['-s', '-t', '-H', '-P', '-L'].includes(flag)) tail.shift();
        }
        if (!['devices', 'version', 'help'].includes(tail[0])) optIn.add('Android device/emulator workflow');
      }
      if (bin === 'emulator' && !args.includes('-list-avds')) optIn.add('Device/emulator/UI workflow');
      if (['avdmanager', 'maestro', 'axe', 'idb', 'ideviceinstaller', 'ios-deploy'].includes(bin)) optIn.add('Device/emulator/UI workflow');
      if (bin.startsWith('argent')) optIn.add('Argent');
      if (bin === 'open' && args.some(a => /^(Simulator|Simulator.app)$/.test(path.basename(a)))) optIn.add('iOS simulator workflow');
      if (bin === 'osascript' && /Simulator|System Events/.test(joined)) optIn.add('Native UI automation');
      if ((bin === 'xctrace' || (bin === 'xcrun' && args[0] === 'xctrace')) && args.includes('record')) optIn.add('Device/native UI profiling');
      if ((bin === 'playwright' || (['npx', 'npm', 'pnpm', 'yarn', 'bun'].includes(bin) && args.includes('playwright'))) && args.includes('test')) optIn.add('Browser UI QA');
      if (['npm', 'pnpm', 'yarn', 'bun'].includes(bin)) {
        if (/(?:^|\s)(test(?::[\w-]+)?|check(?::[\w-]+)?|typecheck|lint)(?:\s|$)/.test(joined)) verification = true;
        const run = args.findIndex(arg => ['run', 'run-script'].includes(arg));
        const script = run >= 0 ? args[run + 1] : args[0] === 'test' ? 'test' : undefined;
        const prefix = args.findIndex(arg => ['--prefix', '--dir', '-C'].includes(arg));
        const owner = directory && prefix >= 0 && args[prefix + 1] ? path.resolve(directory, args[prefix + 1]) : directory;
        if (script && owner) {
          const scriptKey = `${owner}/${script}`;
          if (!visitedScripts.has(scriptKey)) {
            visitedScripts.add(scriptKey);
            try {
              const recipe = JSON.parse(fs.readFileSync(path.join(owner, 'package.json'), 'utf8')).scripts?.[script];
              if (typeof recipe === 'string') inspect(recipe, depth + 1, owner);
            } catch (error) { if (error.code !== 'ENOENT') throw error; }
          }
        }
      }
      if (bin === 'node' && args.includes('--test')) verification = true;
      if (['pytest', 'shellcheck', 'actionlint', 'swiftlint'].includes(bin) || (bin.startsWith('python') && /unittest|pytest/.test(joined))) verification = true;
      const scripts = [program, ...(['bash', 'sh', 'python3', 'python', 'node'].includes(bin) ? args : [])].map(a => path.basename(a));
      if (scripts.some(a => /^(check-|validate|test[_-]).*\.(sh|py|mjs)$/.test(a))) verification = true;
      if (scripts.some(a => /(?:run-.*(?:ui-e2e|ui-tests|device|instrumentation)|run-wear-emulator|physical-export|capture-.*(?:screenshots?|paired-qa|battery-evidence|generated-apk)|generate-macos-app-store-screenshots|capture-marketing).*\.(sh|py|mjs|ts)$/.test(a))) optIn.add('Device/emulator/UI script');
      // Wrapper commands are inspected too; quoting is not an opt-in bypass.
      if (scripts.includes('verification.mjs') && args.includes('run') && args.includes('--command')) inspect(args[args.indexOf('--command') + 1] ?? '', depth + 1, directory);
    }
  };
  if (typeof input.command === 'string' && /(?:^|[._/])(?:bash|powershell|exec_command)$/.test(tool)) inspect(input.command);
  return { verification: verification || optIn.size > 0, optIn: [...optIn], broad: [...broad] };
}

export function invocationDecision(invocation, plan, { approved = false } = {}) {
  const assessment = assessInvocation(invocation);
  if (assessment.verification && !plan) return { ...assessment, block: 'Choose a verification plan before running checks.' };
  if (assessment.optIn.length && !approved) return { ...assessment, block: `Explicit current-task user authorization required: ${assessment.optIn.join(', ')}.` };
  const warnings = assessment.broad.length && !plan?.reason?.trim()
    ? ['Broad qualification has no recorded reason. Prefer focused feedback or record the affected/qualification rationale.'] : [];
  return { ...assessment, warnings };
}

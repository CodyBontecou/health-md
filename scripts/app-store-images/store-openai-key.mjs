#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import process from "node:process";

const DEFAULT_SERVICE = "appstore-ai-images.openai-api-key";
const DEFAULT_ACCOUNT = "default";

const args = process.argv.slice(2);
const useStdin = args.includes("--stdin");
const service = valueFor("--service") ?? DEFAULT_SERVICE;
const account = valueFor("--account") ?? DEFAULT_ACCOUNT;

function valueFor(flag) {
  const inline = args.find((arg) => arg.startsWith(`${flag}=`));
  if (inline) return inline.slice(flag.length + 1);
  const index = args.indexOf(flag);
  if (index >= 0) return args[index + 1];
  return undefined;
}

async function readAllStdin() {
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  return Buffer.concat(chunks).toString("utf8").trim();
}

function readSecret(prompt) {
  return new Promise((resolve) => {
    const stdin = process.stdin;
    const wasRaw = Boolean(stdin.isRaw);
    let value = "";

    process.stdout.write(prompt);
    stdin.setEncoding("utf8");
    if (stdin.isTTY) stdin.setRawMode(true);
    stdin.resume();

    const cleanup = () => {
      stdin.off("data", onData);
      if (stdin.isTTY) stdin.setRawMode(wasRaw);
      process.stdout.write("\n");
    };

    const onData = (chunk) => {
      for (const char of chunk) {
        if (char === "\u0003") {
          cleanup();
          process.exit(130);
        }
        if (char === "\r" || char === "\n") {
          cleanup();
          resolve(value.trim());
          return;
        }
        if (char === "\u007f" || char === "\b") {
          value = value.slice(0, -1);
          continue;
        }
        value += char;
      }
    };

    stdin.on("data", onData);
  });
}

function storeInKeychain(key) {
  // `security add-generic-password -w` does not prompt for a value when
  // launched without a TTY; it silently stores an empty password. Pass the
  // value as the option argument instead. spawnSync avoids shell expansion,
  // and no output or repository file receives the secret.
  const result = spawnSync(
    "security",
    ["add-generic-password", "-a", account, "-s", service, "-U", "-w", key],
    {
      encoding: "utf8",
      stdio: ["ignore", "pipe", "pipe"],
    },
  );

  if (result.status !== 0) {
    throw new Error((result.stderr || result.stdout || "security command failed").trim());
  }
}

const key = useStdin ? await readAllStdin() : await readSecret("OpenAI API key: ");

if (!key) {
  console.error("No key provided; nothing stored.");
  process.exit(1);
}

if (!key.startsWith("sk-")) {
  console.warn("Warning: key does not start with sk-. Storing anyway.");
}

storeInKeychain(key);
console.log(`Stored OpenAI API key in macOS Keychain service '${service}' account '${account}'.`);
console.log("Future runs can use `npm --prefix scripts/app-store-images run generate` without exporting OPENAI_API_KEY.");

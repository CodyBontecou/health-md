#!/usr/bin/env node
import { spawnSync } from "node:child_process";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";

const toolDir = path.dirname(fileURLToPath(import.meta.url));

function argument(name: string): string | undefined {
  const index = process.argv.indexOf(name);
  return index === -1 ? undefined : process.argv[index + 1];
}

const locale = argument("--locale");
if (!locale) throw new Error("--locale is required.");
const generate = process.argv.includes("--generate");
const force = process.argv.includes("--force");
const requestedSlides = argument("--slides");
const slides = requestedSlides
  ? requestedSlides.split(",").map(Number)
  : [1, 2, 3, 4, 5, 6, 7, 8, 9];
if (slides.some((slide) => !Number.isInteger(slide) || slide < 1 || slide > 9)) {
  throw new Error("--slides must be a comma-separated subset of 1 through 9.");
}

console.log(`${generate ? "Generating" : "Planning"} ${slides.length} ${locale} localized slide(s).`);
if (generate) {
  console.log(`Paid image edits planned: ${slides.length}; approximate medium-quality cost: $${(slides.length * 0.04).toFixed(2)} before manual retries.`);
}

const tsx = path.join(toolDir, "node_modules/.bin/tsx");
for (const slide of slides) {
  const args = [
    path.join(toolDir, "edit-localized-slide.ts"),
    "--locale", locale,
    "--slide", String(slide),
  ];
  if (generate) args.push("--generate");
  if (force) args.push("--force");
  const result = spawnSync(tsx, args, { cwd: toolDir, stdio: "inherit", env: process.env });
  if (result.status !== 0) process.exit(result.status ?? 1);
}

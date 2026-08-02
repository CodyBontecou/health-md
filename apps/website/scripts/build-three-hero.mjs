#!/usr/bin/env node
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { build } from 'esbuild';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const entry = path.join(ROOT, 'scripts', 'landing-three.source.js');
const outfile = path.join(ROOT, 'assets', 'landing-three.bundle.js');

const result = await build({
  entryPoints: [entry],
  outfile,
  bundle: true,
  minify: true,
  format: 'esm',
  platform: 'browser',
  target: ['es2022'],
  legalComments: 'eof',
  banner: {
    js: '/*! Health.md documentation strand; Three.js portions © 2010-2026 Three.js authors, MIT License. */',
  },
  metafile: true,
});

const output = Object.values(result.metafile.outputs)[0];
console.log(`Bundled documentation strand: ${output.bytes} bytes -> ${path.relative(ROOT, outfile)}`);

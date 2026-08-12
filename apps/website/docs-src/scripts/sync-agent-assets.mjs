#!/usr/bin/env node
import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import process from 'node:process';
import { fileURLToPath } from 'node:url';

const SCRIPT_DIR = path.dirname(fileURLToPath(import.meta.url));
const DOCS_ROOT = path.resolve(SCRIPT_DIR, '..');
const REPOSITORY_ROOT = path.resolve(DOCS_ROOT, '../../..');
const PUBLIC_ROOT = path.join(DOCS_ROOT, 'public');

const SOURCES = {
  provenance: path.join(DOCS_ROOT, 'reference-source.json'),
  macTools: path.join(PUBLIC_ROOT, 'agents/mcp/mac-tools-v1.json'),
  portableTools: path.join(REPOSITORY_ROOT, 'apps/cli/crates/healthmd-mcp/assets/mcp-tools-v1.json'),
  skill: path.join(REPOSITORY_ROOT, '.agents/skills/healthmd-cli/SKILL.md'),
};

const OUTPUTS = {
  provenance: 'reference/source-manifest.json',
  provenanceV1: 'reference/source-manifest-v1.json',
  portableTools: 'agents/mcp/portable-tools-v1.json',
  skill: 'agents/skills/healthmd-cli/v1/SKILL.md',
  skillManifest: 'agents/skills/healthmd-cli/manifest.json',
  agentManifest: 'agents/manifest.json',
};

function usage() {
  return 'Usage: node scripts/sync-agent-assets.mjs --write|--check';
}

function parseMode() {
  const arguments_ = process.argv.slice(2);
  if (arguments_.length !== 1 || !['--write', '--check'].includes(arguments_[0])) {
    throw new Error(usage());
  }
  return arguments_[0].slice(2);
}

function sha256(buffer) {
  return createHash('sha256').update(buffer).digest('hex');
}

function canonicalJSON(value) {
  return Buffer.from(`${JSON.stringify(value, null, 2)}\n`);
}

function artifact(pathname, buffer, extra = {}) {
  return {
    ...extra,
    path: pathname,
    media_type: pathname.endsWith('.json') ? 'application/json' : 'text/markdown',
    bytes: buffer.length,
    sha256: sha256(buffer),
  };
}

async function readRequired(source, label) {
  try {
    return await fs.readFile(source);
  } catch (error) {
    throw new Error(`Missing ${label}: ${source} (${error.message})`);
  }
}

function parseToolCatalog(buffer, label, expectedCount) {
  let tools;
  try {
    tools = JSON.parse(buffer.toString('utf8'));
  } catch (error) {
    throw new Error(`${label} does not contain valid JSON: ${error.message}`);
  }
  if (!Array.isArray(tools) || tools.length !== expectedCount) {
    throw new Error(`${label} must contain exactly ${expectedCount} tools.`);
  }
  const names = tools.map((tool) => tool?.name);
  if (names.some((name) => typeof name !== 'string') || new Set(names).size !== names.length) {
    throw new Error(`${label} contains missing or duplicate tool names.`);
  }
  return names;
}

async function expectedOutputs() {
  const [provenance, macTools, portableTools, skill] = await Promise.all([
    readRequired(SOURCES.provenance, 'reference provenance manifest'),
    readRequired(SOURCES.macTools, 'generated Mac MCP tool catalog'),
    readRequired(SOURCES.portableTools, 'portable MCP tool catalog'),
    readRequired(SOURCES.skill, 'Health.md CLI skill'),
  ]);

  const macToolNames = parseToolCatalog(macTools, 'Mac MCP tool catalog', 21);
  const portableToolNames = parseToolCatalog(portableTools, 'portable MCP tool catalog', 19);
  const skillArtifact = artifact('/agents/skills/healthmd-cli/v1/SKILL.md', skill, {
    version: 1,
  });
  const skillManifest = canonicalJSON({
    schema: 'healthmd.agent_skill_manifest',
    schema_version: 1,
    name: 'healthmd-cli',
    availability: 'preview_until_public_healthmd_cli_release',
    install_as: 'healthmd-cli/SKILL.md',
    latest: skillArtifact,
    versions: [skillArtifact],
    source: {
      repository: 'https://github.com/CodyBontecou/health-md',
      path: '.agents/skills/healthmd-cli/SKILL.md',
    },
  });

  const agentManifest = canonicalJSON({
    schema: 'healthmd.agent_assets',
    schema_version: 1,
    artifacts: [
      artifact('/agents/mcp/mac-tools-v1.json', macTools, {
        id: 'mac_mcp_tools',
        availability: 'released',
        catalog_version: 1,
        profile: 'bundled_mac',
        tool_count: macToolNames.length,
        tool_names: macToolNames,
      }),
      artifact('/agents/mcp/portable-tools-v1.json', portableTools, {
        id: 'portable_mcp_tools',
        availability: 'preview_until_public_healthmd_cli_release',
        catalog_version: 1,
        profile: 'local_direct',
        tool_count: portableToolNames.length,
        tool_names: portableToolNames,
      }),
      artifact('/agents/skills/healthmd-cli/manifest.json', skillManifest, {
        id: 'healthmd_cli_skill_manifest',
        availability: 'preview_until_public_healthmd_cli_release',
        manifest_version: 1,
      }),
      artifact('/docs/reference/source-manifest.json', provenance, {
        id: 'reference_provenance',
        availability: 'released',
        manifest_version: 1,
      }),
    ],
  });

  return new Map([
    [OUTPUTS.provenance, provenance],
    [OUTPUTS.provenanceV1, provenance],
    [OUTPUTS.portableTools, portableTools],
    [OUTPUTS.skill, skill],
    [OUTPUTS.skillManifest, skillManifest],
    [OUTPUTS.agentManifest, agentManifest],
  ]);
}

async function main() {
  const mode = parseMode();
  const expected = await expectedOutputs();
  const differences = [];

  for (const [relative, buffer] of expected) {
    const destination = path.join(PUBLIC_ROOT, ...relative.split('/'));
    if (mode === 'write') {
      await fs.mkdir(path.dirname(destination), { recursive: true });
      await fs.writeFile(destination, buffer);
      continue;
    }
    const actual = await fs.readFile(destination).catch(() => null);
    if (!actual) differences.push(`missing ${relative}`);
    else if (!actual.equals(buffer)) differences.push(`changed ${relative}`);
  }

  if (differences.length > 0) {
    throw new Error(`Published agent assets are stale:\n${differences.join('\n')}\nRun npm run agent-assets:sync.`);
  }
  console.log(`${mode === 'write' ? 'Updated' : 'Verified'} ${expected.size} published agent assets.`);
}

main().catch((error) => {
  console.error(`sync-agent-assets: ${error.message}`);
  process.exitCode = 1;
});

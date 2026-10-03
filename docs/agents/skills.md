# Health.md agent skills

Health.md publishes Agent Skills from [`.agents/skills`](../../.agents/skills). A skill is an instruction bundle for a compatible coding agent; it does **not** install the `healthmd` binaries, configure MCP, pair a phone, or grant access to health data.

## Available skills

| Skill | Intended audience | Purpose |
|---|---|---|
| [`healthmd-cli`](../../.agents/skills/healthmd-cli/SKILL.md) | Health.md users | Use the installed CLI and portable MCP server for bounded, user-authorized queries and exports. This is the default consumer skill published on [skills.sh](https://skills.sh/CodyBontecou/health-md/healthmd-cli). |
| [`healthmd-cli-operator`](../../.agents/skills/healthmd-cli-operator/SKILL.md) | Operators | Run and troubleshoot direct iPhone pairing, exports, extraction, and durable-job recovery. |
| [`healthmd-cli-development`](../../.agents/skills/healthmd-cli-development/SKILL.md) | Contributors | Change the Rust CLI/MCP implementation, direct protocol, or iPhone direct service. |
| [`healthmd-cli-qa`](../../.agents/skills/healthmd-cli-qa/SKILL.md) | Contributors and release testers | Validate automated compatibility gates and physical-device CLI/MCP workflows. |

Install only the skill that matches the task. In particular, end users should choose `healthmd-cli`, not a development or QA skill.

## Install from skills.sh/GitHub

Run the Skills CLI from the project where the agent should use Health.md:

```bash
npx skills add CodyBontecou/health-md@healthmd-cli
```

The skills.sh listing is a directory page; installation resolves the public GitHub repository. Review the skill source before installation because agent skills can influence commands an agent runs.

To install a contributor skill, replace the name after `@`:

```bash
npx skills add CodyBontecou/health-md@healthmd-cli-operator
npx skills add CodyBontecou/health-md@healthmd-cli-development
npx skills add CodyBontecou/health-md@healthmd-cli-qa
```

List the repository's discoverable skills without installing them:

```bash
npx skills add CodyBontecou/health-md --list
```

Update an installed project skill explicitly:

```bash
npx skills update healthmd-cli --project --yes
```

Use `--global` instead of the default project installation only when every project for that local agent should receive the same Health.md guidance.

## Install from a checkout

Contributors can install from the current checkout to test unpublished skill changes:

```bash
npx skills add . --skill healthmd-cli
```

This does not publish the checkout or send health data. It only installs the selected instruction bundle into a supported local agent directory.

## Install the software separately

Install the CLI by following [`apps/cli/README.md`](../../apps/cli/README.md), then configure the portable MCP server with `healthmd setup codex` or the documented manual host configuration. Pairing and platform health permissions remain explicit user actions on the mobile device.

The consumer skill requires least-privilege scopes, bounded output, explicit missingness and units, health-free diagnostics by default, and no medical diagnosis. Never include raw health payloads, credentials, or user paths in issues, logs, or skill evaluations.

## Publishing contract

The canonical consumer source is [`.agents/skills/healthmd-cli/SKILL.md`](../../.agents/skills/healthmd-cli/SKILL.md). The website publishes immutable, checksum-backed versions under `apps/website/docs-src/public/agents/skills/healthmd-cli/`; the latest version and SHA-256 digest are recorded in its `manifest.json`.

After an intentional consumer-skill change:

1. preserve every already-published version;
2. add a new version in `apps/website/docs-src/scripts/sync-agent-assets.mjs`;
3. run `node apps/website/docs-src/scripts/sync-agent-assets.mjs --write`;
4. run the website publishing and localization tests;
5. install the selected skill from a clean temporary project to verify discovery and packaged files.

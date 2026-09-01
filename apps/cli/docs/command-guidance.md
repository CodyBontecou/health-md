# CLI discovery, guidance, and error contract

Health.md's shell CLI is designed for both humans and software agents. A command that is merely
incomplete is a **discovery request**, not a failed health-data request. Discovery is local,
health-free, and returns enough structure to form a valid next invocation.

## Discovery without side effects

These incomplete commands exit successfully and do not open credentials, start a listener, mutate
trust, or contact a mobile device:

```bash
healthmd export
healthmd extract
healthmd query
healthmd query healthmd_sleep_sessions
healthmd resume
healthmd cancel
healthmd direct
healthmd direct unpair
healthmd direct reset-trust
healthmd mcp
healthmd setup
```

In an interactive terminal, the CLI renders concise headings, argument summaries, examples, and next
steps. When stdout is piped or redirected, it preserves the stable `healthmd.cli_guidance/1` JSON
contract:

```json
{
  "schema": "healthmd.cli_guidance",
  "schema_version": 1,
  "status": "guidance",
  "command": "healthmd export",
  "message": "The export request is incomplete. Choose the missing values below; no device was contacted.",
  "request_sent": false,
  "missing": [],
  "examples": [],
  "next_actions": []
}
```

Fields are additive. Agents should branch on `schema`, `schema_version`, and `status`, then use the
structured requirements rather than scraping `message`. Global `--json` forces this representation
even in a terminal; global `--human` forces readable text even through a pipe or pager. Raw JSON,
JSONL, and generated-file artifacts retain their exact product format rather than passing through
the human renderer.

### Export discovery

`healthmd export` explains both valid modes:

- **Raw:** exactly one date selection plus `--raw`; `--output` is optional.
- **Generated files:** exactly one date selection plus an existing absolute `--destination`.

It returns `required_choices`, platform notes, accepted settings, and `argv_template` examples. A
partially formed request also reports only what is still missing:

```bash
healthmd export --yesterday
```

This requests guidance to choose either `--raw` or `--destination`; it does not inspect pairing or
contact a source.

### Typed-query discovery

`healthmd query` lists every fixed query operation from the same registry used by MCP. Selecting an
operation without `--arguments` shows a concise argument synopsis and executable examples in a
terminal:

```bash
healthmd query healthmd_sleep_sessions
```

The human view includes the operation name, purpose, required arguments, types, defaults, and copyable
commands. Add `--json`, or pipe the command, to receive the complete `input_schema`, including nested
shapes, bounds, enums, structured example arguments, and shell-safe `argv` arrays. Independent MCP
inspection follows the same rule through `healthmd mcp schema`.

After resolving the user's actual dates, execute the returned shape:

```bash
healthmd query healthmd_sleep_sessions \
  --arguments '{"dates":{"type":"all_available"},"all_pages":true}'
```

The schema's dates are illustrative. Never silently substitute example dates for a user's request.

### Destructive-command discovery

`healthmd direct reset-trust` is intentionally non-mutating unless `--confirm` is present. Its
guidance explains what will be removed and what to inspect first. Likewise, `resume`, `cancel`, and
`direct unpair` explain the required durable job or device identifier when it is omitted.

## Text help

Explicit help and version requests remain human-readable text and exit successfully:

```bash
healthmd --help
healthmd export --help
healthmd extract --help
healthmd query --help
healthmd resume --help
healthmd direct pair --help
healthmd mcp schema --help
healthmd --version
```

Help documents every flag, valid enum, conflict, date rule, timeout bound, mode, and representative
example. Use `--json` when a program needs stable fields, `--human` when readable text must survive a
pipe, and `--help` for a complete terminal reference.

## Actionable failures

A malformed, contradictory, unsafe, or operationally unsuccessful request still exits nonzero so
automation cannot mistake failure for success. Interactive terminals receive a concise error,
accepted syntax, and recovery steps. Piped output and `--json` receive one `healthmd.cli_error/1` JSON
document on stdout:

```json
{
  "schema": "healthmd.cli_error",
  "schema_version": 1,
  "status": "failure",
  "backend": "direct",
  "error": "invalid_request",
  "error_kind": "argument_conflict",
  "message": "Two supplied arguments cannot be used together. Choose one documented request shape.",
  "command": "healthmd export",
  "request_sent": false,
  "help_command": "healthmd export --help",
  "accepted_arguments": [],
  "guidance": {},
  "next_actions": []
}
```

Parser errors never embed Clap's multiline terminal rendering inside a JSON string. They use a
stable `error_kind`, accepted forms, command-specific guidance, and bounded next actions. Unknown or
invalid user-provided values are not echoed, which prevents accidental health data, paths, or other
private shell values from entering diagnostics.

Semantic validation errors retain a concise reason. For example, running a sleep operation with an
empty arguments object reports `dates are required` and embeds that exact operation's schema under
`guidance`.

Operational errors provide code-specific recovery, for example:

- multiple paired devices → list devices, then retry with global `--device <UUID>`;
- unavailable foreground source → keep Health.md open, run `healthmd status`, inspect trust;
- paused durable export → inspect `status --job`, then `resume` the exact job;
- cancellation pending → keep the source foreground and inspect acknowledgement state;
- invalid native trust → inspect devices before entering explicit reset guidance;
- unsupported Nearby transport → retry with portable `--transport manual-ip`.

Messages remain health-free. Do not attach raw health output, source records, credentials, user
paths, or user-data dates to support logs. `healthmd mcp serve*` reserves stdout for MCP JSON-RPC;
server startup and transport diagnostics therefore remain health-free stderr with a nonzero exit
rather than writing a CLI envelope into the protocol stream.

## Output selection

| Invocation | Structured command output |
|---|---|
| Interactive terminal | Human-readable text |
| Pipe or redirect | Pretty-printed JSON |
| `--json` | JSON regardless of terminal detection |
| `--human` | Human-readable text regardless of terminal detection |
| `healthmd mcp serve*` | MCP JSON-RPC only; formatting flags do not alter the protocol |
| Raw JSON/JSONL or generated-file artifact | Exact artifact bytes |

`--json` and `--human` conflict. Explicit `--help` and `--version` always remain text.

## Exit status

| Exit | Meaning |
|---:|---|
| `0` | Successful operation, explicit text help/version, or non-network guidance |
| `1` | Semantic validation, source/runtime, durable-job, output, or integrity failure; also an unaccepted partial result |
| `2` | Command-line parser failure such as an unknown flag, missing flag value, invalid UUID, or conflict |

A validated partial raw result can have product-specific output behavior; `--allow-partial` is the
explicit opt-in where supported.

## Recommended agent loop

1. If the command shape is unknown, invoke the command at the narrowest known level, such as
   `healthmd export`, `healthmd query`, or `healthmd direct`.
2. Require `status == "guidance"` and `request_sent == false` before treating the response as local
   discovery.
3. Fill every item in `missing` or `required` and choose only documented mutually exclusive modes.
4. For typed queries, inspect the selected operation first and validate the JSON object against
   `input_schema`.
5. Ask for user approval before exports, resume, cancellation, or trust mutation when the host's
   policy requires it.
6. Execute the complete request. On `status == "failure"`, branch on `error`, follow
   `next_actions`, and do not blindly retry mutations with unknown outcomes.
7. Preserve semantic IDs, units, provenance, coverage, missingness, and platform limitations in the
   successful result.

This contract does not turn real failures into successful empty data. It makes discovery safe and
makes every retained failure explicit, machine-readable, bounded, and recoverable.

/** Frozen Stage1 primary/accepted-source literals before serializer implementation.
 * Generic serde Value compact or explicit compact LF; pure ownership is not data authority.
 * No candidate/parser/renderer/check/oracle executed to produce expectations. */
import type * as Result from "effect/Result";
import type { ExactJsonValueFailure } from "../src/serialization/exact-json-value.js";
export interface CanonicalJsonSerializer {
  readonly encode: (handle: unknown, policy: unknown) => Result.Result<Uint8Array, ExactJsonValueFailure>;
}
export type CreateCanonicalJsonSerializer = (codec: unknown, readerToken: unknown) => Result.Result<CanonicalJsonSerializer, ExactJsonValueFailure>;
export const canonicalJsonContract = {
  "construction": "createCanonicalJsonSerializer(codec: unknown, readerToken: unknown): Result.Result<CanonicalJsonSerializer, ExactJsonValueFailure>",
  "encode": "encode(handle: unknown, policy: unknown): Result.Result<Uint8Array, ExactJsonValueFailure>",
  "policies": [
    "serde_value_compact",
    "serde_value_compact_lf"
  ],
  "failure": {
    "_tag": "ExactJsonValueFailure",
    "code": "invalid_json_value"
  },
  "construction_authority": "Call original accepted captureExactJsonValueReader(codec,readerToken) once; it authenticates codec and samefactory token WeakMaps BEFOREproperties. Capture original bound read function from its authentic frozen success. Never accept injected visitor/reader/function/AST/property-based codec; parser needs no edits.",
  "ownership": "Encode validates primitive exact policy before graph access; original captured reader authenticates handle membership before properties. Foreign/crossfactory/Proxy/revoked Proxy handles fixedfailure without traps. Samefactory child accepted. Pure handles have no grant or Effect Scope authority; caller operation owns life/scope. No reader export through consumer facade.",
  "algorithm": "Walk original immutable owned graph; preflight exact complete encoded byte count including punctuation/escapes/scalar lexemes and optional one LF; cap1048576 before allocating output bytecarrier; second original graph walk fills one fresh owned Uint8Array. Temporary bounded scalar renderer bytes may be used in preflight and counted boundedly; no partial carrier publication. No toJSON/getter/callback/provider reflection. No JSON.stringify/JSNumber numeric conversion/duplicate scalar renderer.",
  "number_binding": "Call original accepted serializeExactJsonNumber for every source-class numeric: f64=>binary64 bits, i64=>signed_integer decimal, u64=>unsigned_integer decimal. Preserve original source class, negativezero, finite exactbits and widened integers disallowed. Source profile default nonfloatroundtrip parser class distinct from shortest serializer lexical stage.",
  "string_and_keys": "Source ser.rs escape table: only0..31/quote/reverse solidus, short b/t/n/f/r, othercontrols lowercase u00xx; solidus/DEL/U2028/U2029/Unicode unchanged strictUTF8, no normalization. Object entries from original parser immutable UTF8lexical BTreeorder, never integer-key JSenumeration/UTF16sort; arrays unchanged. Unknown/profile/version/time strings and numeric values generic preserved, no schema inference.",
  "bounds": {
    "complete_encoded_bytes_with_LF": 1048576,
    "maximum_reachable_nodes": 65536,
    "maximum_container_nesting": 127,
    "aggregate_decoded_key_string_UTF8_bytes": 262144,
    "maximum_number_lexeme_bytes": 24
  },
  "work_policy": "Parser enforces all original cumulative admission/work budgets including duplicates and raw reparses. Serializer at most two bounded reachable graph traversals and bounded scalar render calls; no recursive unbounded reparse or sorting. Bounded temporary shallow reader views allowed, not fulloutput beforepreflight. Outputcap difference private profile not general Rust/public parity.",
  "feature_scope": "serde_json1.0.151 actual defaultgraphs std/raw_value (+alloc core); absentfloat_roundtrip/arbitrary_precision/preserve_order/unbounded_depth. First RawValue parser exception already applied to owned AST; serializer does not redo first-key interpretation or reinterpret ordinary laterkey.",
  "profile_limits": "Compact/LF-only Value serde profile. No pretty/TOML/PNG/Foundation/Kotlin/native/schema/time/prefix/public API/transport bytes beyond generic JSON and explicit LF. Historical43/26consumer cohort unchanged; numeric46/28 and Value49/30 unadopted by CLI/MCP."
} as const;
export const retainedSerializerPacketProposals = [
  {
    "case_id": "serialize-negative-zero",
    "input": {
      "owned_input": "[-0,1,1.0,1e0]"
    },
    "expected": {
      "compact": "[-0.0,1,1.0,1.0]"
    },
    "source_basis": "F64/I64/U64 classes + accepted scalar renderer",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-compact-lf",
    "input": {
      "owned_input": "{\"b\":1,\"a\":2}",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "utf8": "{\"a\":2,\"b\":1}\n"
    },
    "source_basis": "lib.rs fixture newline is explicit profile not universal",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-compact-no-lf",
    "input": {
      "owned_input": "{}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{}"
    },
    "source_basis": "semantic canonical_result_bytes and MCP text no LF",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-large-integer",
    "input": {
      "owned_input": "9007199254740993"
    },
    "expected": {
      "utf8": "9007199254740993"
    },
    "source_basis": "existing u64 renderer",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-escaped-string",
    "input": {
      "owned_input": "\"a\\n\\\"\\\\\""
    },
    "expected": {
      "utf8": "\"a\\n\\\"\\\\\""
    },
    "source_basis": "ser escape table",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-foreign-handle",
    "input": {
      "harness": "other codec factory handle/proxy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0
    },
    "source_basis": "factory membership before properties",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-output-owned",
    "input": {
      "owned_input": "[1]",
      "harness": "mutate first returned bytes then serialize again"
    },
    "expected": {
      "second_utf8": "[1]",
      "same_buffer": false
    },
    "source_basis": "fresh bounded output ownership",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-invalid-profile",
    "input": {
      "owned_input": "{}",
      "policy": "foundation_ordered_json"
    },
    "expected": {
      "error": "invalid_json_value"
    },
    "source_basis": "public ordered profiles excluded",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "serialize-output-limit",
    "input": {
      "harness": "valid input whose escaped output exceeds configured1MiB cap"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_output_published": false
    },
    "source_basis": "preflight complete encoded size then owned allocation",
    "status": "proposed_independent_literal_review_required"
  }
] as const;
export const canonicalJsonVectors = [
  {
    "case_id": "serialize-ascii-000",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0000\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0000\"",
      "utf8_hex": "225c753030303022",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-001",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0001\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0001\"",
      "utf8_hex": "225c753030303122",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-002",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0002\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0002\"",
      "utf8_hex": "225c753030303222",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-003",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0003\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0003\"",
      "utf8_hex": "225c753030303322",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-004",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0004\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0004\"",
      "utf8_hex": "225c753030303422",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-005",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0005\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0005\"",
      "utf8_hex": "225c753030303522",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-006",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0006\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0006\"",
      "utf8_hex": "225c753030303622",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-007",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0007\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0007\"",
      "utf8_hex": "225c753030303722",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-008",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0008\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\b\"",
      "utf8_hex": "225c6222",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-009",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0009\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\t\"",
      "utf8_hex": "225c7422",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-010",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u000a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\n\"",
      "utf8_hex": "225c6e22",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-011",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u000b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u000b\"",
      "utf8_hex": "225c753030306222",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-012",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u000c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\f\"",
      "utf8_hex": "225c6622",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-013",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u000d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\r\"",
      "utf8_hex": "225c7222",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-014",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u000e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u000e\"",
      "utf8_hex": "225c753030306522",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-015",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u000f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u000f\"",
      "utf8_hex": "225c753030306622",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-016",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0010\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0010\"",
      "utf8_hex": "225c753030313022",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-017",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0011\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0011\"",
      "utf8_hex": "225c753030313122",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-018",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0012\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0012\"",
      "utf8_hex": "225c753030313222",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-019",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0013\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0013\"",
      "utf8_hex": "225c753030313322",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-020",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0014\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0014\"",
      "utf8_hex": "225c753030313422",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-021",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0015\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0015\"",
      "utf8_hex": "225c753030313522",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-022",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0016\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0016\"",
      "utf8_hex": "225c753030313622",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-023",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0017\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0017\"",
      "utf8_hex": "225c753030313722",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-024",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0018\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0018\"",
      "utf8_hex": "225c753030313822",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-025",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0019\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u0019\"",
      "utf8_hex": "225c753030313922",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-026",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u001a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u001a\"",
      "utf8_hex": "225c753030316122",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-027",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u001b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u001b\"",
      "utf8_hex": "225c753030316222",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-028",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u001c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u001c\"",
      "utf8_hex": "225c753030316322",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-029",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u001d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u001d\"",
      "utf8_hex": "225c753030316422",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-030",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u001e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u001e\"",
      "utf8_hex": "225c753030316522",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-031",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u001f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u001f\"",
      "utf8_hex": "225c753030316622",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-032",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0020\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\" \"",
      "utf8_hex": "222022",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-033",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0021\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"!\"",
      "utf8_hex": "222122",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-034",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0022\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\\"\"",
      "utf8_hex": "225c2222",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-035",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0023\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"#\"",
      "utf8_hex": "222322",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-036",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0024\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"$\"",
      "utf8_hex": "222422",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-037",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0025\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"%\"",
      "utf8_hex": "222522",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-038",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0026\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"&\"",
      "utf8_hex": "222622",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-039",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0027\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"'\"",
      "utf8_hex": "222722",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-040",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0028\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"(\"",
      "utf8_hex": "222822",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-041",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0029\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\")\"",
      "utf8_hex": "222922",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-042",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u002a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"*\"",
      "utf8_hex": "222a22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-043",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u002b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"+\"",
      "utf8_hex": "222b22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-044",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u002c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\",\"",
      "utf8_hex": "222c22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-045",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u002d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"-\"",
      "utf8_hex": "222d22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-046",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u002e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\".\"",
      "utf8_hex": "222e22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-047",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u002f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"/\"",
      "utf8_hex": "222f22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-048",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0030\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"0\"",
      "utf8_hex": "223022",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-049",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0031\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"1\"",
      "utf8_hex": "223122",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-050",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0032\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"2\"",
      "utf8_hex": "223222",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-051",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0033\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"3\"",
      "utf8_hex": "223322",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-052",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0034\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"4\"",
      "utf8_hex": "223422",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-053",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0035\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"5\"",
      "utf8_hex": "223522",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-054",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0036\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"6\"",
      "utf8_hex": "223622",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-055",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0037\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"7\"",
      "utf8_hex": "223722",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-056",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0038\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"8\"",
      "utf8_hex": "223822",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-057",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0039\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"9\"",
      "utf8_hex": "223922",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-058",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u003a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\":\"",
      "utf8_hex": "223a22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-059",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u003b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\";\"",
      "utf8_hex": "223b22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-060",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u003c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"<\"",
      "utf8_hex": "223c22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-061",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u003d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"=\"",
      "utf8_hex": "223d22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-062",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u003e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\">\"",
      "utf8_hex": "223e22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-063",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u003f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"?\"",
      "utf8_hex": "223f22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-064",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0040\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"@\"",
      "utf8_hex": "224022",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-065",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0041\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"A\"",
      "utf8_hex": "224122",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-066",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0042\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"B\"",
      "utf8_hex": "224222",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-067",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0043\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"C\"",
      "utf8_hex": "224322",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-068",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0044\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"D\"",
      "utf8_hex": "224422",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-069",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0045\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"E\"",
      "utf8_hex": "224522",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-070",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0046\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"F\"",
      "utf8_hex": "224622",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-071",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0047\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"G\"",
      "utf8_hex": "224722",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-072",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0048\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"H\"",
      "utf8_hex": "224822",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-073",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0049\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"I\"",
      "utf8_hex": "224922",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-074",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u004a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"J\"",
      "utf8_hex": "224a22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-075",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u004b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"K\"",
      "utf8_hex": "224b22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-076",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u004c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"L\"",
      "utf8_hex": "224c22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-077",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u004d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"M\"",
      "utf8_hex": "224d22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-078",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u004e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"N\"",
      "utf8_hex": "224e22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-079",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u004f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"O\"",
      "utf8_hex": "224f22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-080",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0050\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"P\"",
      "utf8_hex": "225022",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-081",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0051\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"Q\"",
      "utf8_hex": "225122",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-082",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0052\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"R\"",
      "utf8_hex": "225222",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-083",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0053\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"S\"",
      "utf8_hex": "225322",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-084",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0054\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"T\"",
      "utf8_hex": "225422",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-085",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0055\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"U\"",
      "utf8_hex": "225522",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-086",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0056\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"V\"",
      "utf8_hex": "225622",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-087",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0057\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"W\"",
      "utf8_hex": "225722",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-088",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0058\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"X\"",
      "utf8_hex": "225822",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-089",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0059\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"Y\"",
      "utf8_hex": "225922",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-090",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u005a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"Z\"",
      "utf8_hex": "225a22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-091",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u005b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"[\"",
      "utf8_hex": "225b22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-092",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u005c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\\\\"",
      "utf8_hex": "225c5c22",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-093",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u005d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"]\"",
      "utf8_hex": "225d22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-094",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u005e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"^\"",
      "utf8_hex": "225e22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-095",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u005f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"_\"",
      "utf8_hex": "225f22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-096",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0060\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"`\"",
      "utf8_hex": "226022",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-097",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0061\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"a\"",
      "utf8_hex": "226122",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-098",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0062\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"b\"",
      "utf8_hex": "226222",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-099",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0063\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"c\"",
      "utf8_hex": "226322",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-100",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0064\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"d\"",
      "utf8_hex": "226422",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-101",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0065\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"e\"",
      "utf8_hex": "226522",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-102",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0066\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"f\"",
      "utf8_hex": "226622",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-103",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0067\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"g\"",
      "utf8_hex": "226722",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-104",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0068\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"h\"",
      "utf8_hex": "226822",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-105",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0069\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"i\"",
      "utf8_hex": "226922",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-106",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u006a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"j\"",
      "utf8_hex": "226a22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-107",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u006b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"k\"",
      "utf8_hex": "226b22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-108",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u006c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"l\"",
      "utf8_hex": "226c22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-109",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u006d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"m\"",
      "utf8_hex": "226d22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-110",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u006e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"n\"",
      "utf8_hex": "226e22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-111",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u006f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"o\"",
      "utf8_hex": "226f22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-112",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0070\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"p\"",
      "utf8_hex": "227022",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-113",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0071\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"q\"",
      "utf8_hex": "227122",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-114",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0072\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"r\"",
      "utf8_hex": "227222",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-115",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0073\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"s\"",
      "utf8_hex": "227322",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-116",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0074\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"t\"",
      "utf8_hex": "227422",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-117",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0075\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"u\"",
      "utf8_hex": "227522",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-118",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0076\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"v\"",
      "utf8_hex": "227622",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-119",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0077\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"w\"",
      "utf8_hex": "227722",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-120",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0078\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"x\"",
      "utf8_hex": "227822",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-121",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u0079\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"y\"",
      "utf8_hex": "227922",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-122",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u007a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"z\"",
      "utf8_hex": "227a22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-123",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u007b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"{\"",
      "utf8_hex": "227b22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-124",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u007c\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"|\"",
      "utf8_hex": "227c22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-125",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u007d\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"}\"",
      "utf8_hex": "227d22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-126",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u007e\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"~\"",
      "utf8_hex": "227e22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-ascii-127",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u007f\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\"",
      "utf8_hex": "227f22",
      "encoded_bytes": 3,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json1.0.151 ser.rs1766–1799/2147–2166 exact escape table; lowercase hex for nonshort controls, no solidus/DEL escaping"
  },
  {
    "case_id": "serialize-unicode-u0080",
    "input": {
      "representation": "text",
      "owned_input": "\"\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\"",
      "utf8_hex": "22c28022",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-u07ff",
    "input": {
      "representation": "text",
      "owned_input": "\"߿\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"߿\"",
      "utf8_hex": "22dfbf22",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-u0800",
    "input": {
      "representation": "text",
      "owned_input": "\"ࠀ\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"ࠀ\"",
      "utf8_hex": "22e0a08022",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-before-surrogate",
    "input": {
      "representation": "text",
      "owned_input": "\"퟿\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"퟿\"",
      "utf8_hex": "22ed9fbf22",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-after-surrogate",
    "input": {
      "representation": "text",
      "owned_input": "\"\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\"",
      "utf8_hex": "22ee808022",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-uFFFF",
    "input": {
      "representation": "text",
      "owned_input": "\"￿\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"￿\"",
      "utf8_hex": "22efbfbf22",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-u10000",
    "input": {
      "representation": "text",
      "owned_input": "\"𐀀\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"𐀀\"",
      "utf8_hex": "22f090808022",
      "encoded_bytes": 6,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-max-scalar",
    "input": {
      "representation": "text",
      "owned_input": "\"􏿿\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"􏿿\"",
      "utf8_hex": "22f48fbfbf22",
      "encoded_bytes": 6,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-line-separator",
    "input": {
      "representation": "text",
      "owned_input": "\" \"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\" \"",
      "utf8_hex": "22e280a822",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-paragraph-separator",
    "input": {
      "representation": "text",
      "owned_input": "\" \"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\" \"",
      "utf8_hex": "22e280a922",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-emoji",
    "input": {
      "representation": "text",
      "owned_input": "\"😀\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"😀\"",
      "utf8_hex": "22f09f988022",
      "encoded_bytes": 6,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-e-composed",
    "input": {
      "representation": "text",
      "owned_input": "\"é\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"é\"",
      "utf8_hex": "22c3a922",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-e-decomposed",
    "input": {
      "representation": "text",
      "owned_input": "\"é\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"é\"",
      "utf8_hex": "2265cc8122",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-unicode-bom-string",
    "input": {
      "representation": "text",
      "owned_input": "\"﻿\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"﻿\"",
      "utf8_hex": "22efbbbf22",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-null",
    "input": {
      "representation": "text",
      "owned_input": "null",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "null",
      "utf8_hex": "6e756c6c",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-true",
    "input": {
      "representation": "text",
      "owned_input": "true",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "true",
      "utf8_hex": "74727565",
      "encoded_bytes": 4,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-false",
    "input": {
      "representation": "text",
      "owned_input": "false",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "false",
      "utf8_hex": "66616c7365",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-empty-string",
    "input": {
      "representation": "text",
      "owned_input": "\"\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\"",
      "utf8_hex": "2222",
      "encoded_bytes": 2,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-empty-array",
    "input": {
      "representation": "text",
      "owned_input": "[]",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "[]",
      "utf8_hex": "5b5d",
      "encoded_bytes": 2,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-empty-object",
    "input": {
      "representation": "text",
      "owned_input": "{}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{}",
      "utf8_hex": "7b7d",
      "encoded_bytes": 2,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-solidus-html",
    "input": {
      "representation": "text",
      "owned_input": "\"<script>&/\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"<script>&/\"",
      "utf8_hex": "223c7363726970743e262f22",
      "encoded_bytes": 12,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-escaped-solidus",
    "input": {
      "representation": "text",
      "owned_input": "\"a\\/b\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"a/b\"",
      "utf8_hex": "22612f6222",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-uppercase-input-escape",
    "input": {
      "representation": "text",
      "owned_input": "\"\\u001B\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"\\u001b\"",
      "utf8_hex": "225c753030316222",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-paired-surrogate",
    "input": {
      "representation": "text",
      "owned_input": "\"\\uD83D\\uDE00\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"😀\"",
      "utf8_hex": "22f09f988022",
      "encoded_bytes": 6,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-string-mixed",
    "input": {
      "representation": "text",
      "owned_input": "\"a\\n\\\"\\\\\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"a\\n\\\"\\\\\"",
      "utf8_hex": "22615c6e5c225c5c22",
      "encoded_bytes": 9,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-decoded-duplicates",
    "input": {
      "representation": "text",
      "owned_input": "{\"a\":1,\"\\u0061\":2}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"a\":2}",
      "utf8_hex": "7b2261223a327d",
      "encoded_bytes": 7,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-decoded-key-nul",
    "input": {
      "representation": "text",
      "owned_input": "{\"\\u0000\":true}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"\\u0000\":true}",
      "utf8_hex": "7b225c7530303030223a747275657d",
      "encoded_bytes": 15,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-integer-key-order",
    "input": {
      "representation": "text",
      "owned_input": "{\"2\":2,\"10\":10,\"1\":1,\"01\":0}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"01\":0,\"1\":1,\"10\":10,\"2\":2}",
      "utf8_hex": "7b223031223a302c2231223a312c223130223a31302c2232223a327d",
      "encoded_bytes": 28,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-utf8-not-utf16-order",
    "input": {
      "representation": "text",
      "owned_input": "{\"𐀀\":1,\"\":2,\"😀\":3}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"\":2,\"𐀀\":1,\"😀\":3}",
      "utf8_hex": "7b22ee8080223a322c22f0908080223a312c22f09f9880223a337d",
      "encoded_bytes": 27,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-normalized-keys-distinct",
    "input": {
      "representation": "text",
      "owned_input": "{\"é\":1,\"e\\u0301\":2}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"é\":2,\"é\":1}",
      "utf8_hex": "7b2265cc81223a322c22c3a9223a317d",
      "encoded_bytes": 16,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-prefix-keys",
    "input": {
      "representation": "text",
      "owned_input": "{\"ab\":2,\"\":0,\"a\":1,\"a\\u0000\":3}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"\":0,\"a\":1,\"a\\u0000\":3,\"ab\":2}",
      "utf8_hex": "7b22223a302c2261223a312c22615c7530303030223a332c226162223a327d",
      "encoded_bytes": 31,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-nested-order",
    "input": {
      "representation": "text",
      "owned_input": "{\"z\":[{\"b\":false,\"a\":null},3],\"a\":{\"2\":2,\"10\":10}}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"a\":{\"10\":10,\"2\":2},\"z\":[{\"a\":null,\"b\":false},3]}",
      "utf8_hex": "7b2261223a7b223130223a31302c2232223a327d2c227a223a5b7b2261223a6e756c6c2c2262223a66616c73657d2c335d7d",
      "encoded_bytes": 50,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-array-order",
    "input": {
      "representation": "text",
      "owned_input": "[3,1,{\"z\":0,\"a\":2},true,null]",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "[3,1,{\"a\":2,\"z\":0},true,null]",
      "utf8_hex": "5b332c312c7b2261223a322c227a223a307d2c747275652c6e756c6c5d",
      "encoded_bytes": 29,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-whitespace-no-prefix",
    "input": {
      "representation": "text",
      "owned_input": " \n\t { \"z\" : [ 1 , 2 ] } \r\n",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"z\":[1,2]}",
      "utf8_hex": "7b227a223a5b312c325d7d",
      "encoded_bytes": 11,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-version-unknown-time-preserved",
    "input": {
      "representation": "text",
      "owned_input": "{\"version\":99,\"unknown\":{\"epoch\":\"9007199254740993\",\"nanos\":123,\"offset\":null},\"schema\":\"future\"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"schema\":\"future\",\"unknown\":{\"epoch\":\"9007199254740993\",\"nanos\":123,\"offset\":null},\"version\":99}",
      "utf8_hex": "7b22736368656d61223a22667574757265222c22756e6b6e6f776e223a7b2265706f6368223a2239303037313939323534373430393933222c226e616e6f73223a3132332c226f6666736574223a6e756c6c7d2c2276657273696f6e223a39397d",
      "encoded_bytes": 97,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-raw-first-carrier",
    "input": {
      "representation": "text",
      "owned_input": "{\"$serde_json::private::RawValue\":\"{\\\"b\\\":1,\\\"a\\\":2}\"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"a\":2,\"b\":1}",
      "utf8_hex": "7b2261223a322c2262223a317d",
      "encoded_bytes": 13,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-raw-first-escaped-key",
    "input": {
      "representation": "text",
      "owned_input": "{\"\\u0024serde_json::private::RawValue\":\"[-0,1.0]\"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "[-0.0,1.0]",
      "utf8_hex": "5b2d302e302c312e305d",
      "encoded_bytes": 10,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-raw-later-ordinary",
    "input": {
      "representation": "text",
      "owned_input": "{\"a\":0,\"$serde_json::private::RawValue\":\" null \"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"$serde_json::private::RawValue\":\" null \",\"a\":0}",
      "utf8_hex": "7b222473657264655f6a736f6e3a3a707269766174653a3a52617756616c7565223a22206e756c6c20222c2261223a307d",
      "encoded_bytes": 49,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-number-first-ordinary",
    "input": {
      "representation": "text",
      "owned_input": "{\"$serde_json::private::Number\":\"1e999\"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{\"$serde_json::private::Number\":\"1e999\"}",
      "utf8_hex": "7b222473657264655f6a736f6e3a3a707269766174653a3a4e756d626572223a223165393939227d",
      "encoded_bytes": 40,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-numeric-number-u64-one",
    "input": {
      "representation": "text",
      "owned_input": "1",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1",
      "utf8_hex": "31",
      "encoded_bytes": 1,
      "fresh_owned_output": true,
      "source_number": {
        "class": "u64",
        "decimal": "1"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-i64-minus-one",
    "input": {
      "representation": "text",
      "owned_input": "-1",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-1",
      "utf8_hex": "2d31",
      "encoded_bytes": 2,
      "fresh_owned_output": true,
      "source_number": {
        "class": "i64",
        "decimal": "-1"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-minus-zero",
    "input": {
      "representation": "text",
      "owned_input": "-0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-0.0",
      "utf8_hex": "2d302e30",
      "encoded_bytes": 4,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "8000000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-decimal-one",
    "input": {
      "representation": "text",
      "owned_input": "1.0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1.0",
      "utf8_hex": "312e30",
      "encoded_bytes": 3,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "3ff0000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-exponent-one",
    "input": {
      "representation": "text",
      "owned_input": "1e0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1.0",
      "utf8_hex": "312e30",
      "encoded_bytes": 3,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "3ff0000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-i64-min",
    "input": {
      "representation": "text",
      "owned_input": "-9223372036854775808",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-9223372036854775808",
      "utf8_hex": "2d39323233333732303336383534373735383038",
      "encoded_bytes": 20,
      "fresh_owned_output": true,
      "source_number": {
        "class": "i64",
        "decimal": "-9223372036854775808"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-u64-max",
    "input": {
      "representation": "text",
      "owned_input": "18446744073709551615",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "18446744073709551615",
      "utf8_hex": "3138343436373434303733373039353531363135",
      "encoded_bytes": 20,
      "fresh_owned_output": true,
      "source_number": {
        "class": "u64",
        "decimal": "18446744073709551615"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-unsafe-integer",
    "input": {
      "representation": "text",
      "owned_input": "9007199254740993",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "9007199254740993",
      "utf8_hex": "39303037313939323534373430393933",
      "encoded_bytes": 16,
      "fresh_owned_output": true,
      "source_number": {
        "class": "u64",
        "decimal": "9007199254740993"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-u64-overflow",
    "input": {
      "representation": "text",
      "owned_input": "18446744073709551616",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1.8446744073709552e+19",
      "utf8_hex": "312e38343436373434303733373039353532652b3139",
      "encoded_bytes": 22,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "43f0000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-negative-underflow",
    "input": {
      "representation": "text",
      "owned_input": "-1e-999",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-0.0",
      "utf8_hex": "2d302e30",
      "encoded_bytes": 4,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "8000000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-number-zero-huge-exponent",
    "input": {
      "representation": "text",
      "owned_input": "0e999999999999999999999",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "0.0",
      "utf8_hex": "302e30",
      "encoded_bytes": 3,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "0000000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-decimal-tenth",
    "input": {
      "representation": "text",
      "owned_input": "0.1",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "0.1",
      "utf8_hex": "302e31",
      "encoded_bytes": 3,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "3fb999999999999a"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-decimal-three-tenths",
    "input": {
      "representation": "text",
      "owned_input": "0.3",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "0.3",
      "utf8_hex": "302e33",
      "encoded_bytes": 3,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "3fd3333333333333"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-u64-overflow-dropped",
    "input": {
      "representation": "text",
      "owned_input": "18446744073709551619",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1.8446744073709552e+19",
      "utf8_hex": "312e38343436373434303733373039353532652b3139",
      "encoded_bytes": 22,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "43f0000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-i64-negative-underflow",
    "input": {
      "representation": "text",
      "owned_input": "-9223372036854775809",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-9.223372036854776e+18",
      "utf8_hex": "2d392e323233333732303336383534373736652b3138",
      "encoded_bytes": 22,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "c3e0000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-u64-max-decimal",
    "input": {
      "representation": "text",
      "owned_input": "18446744073709551615.0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1.8446744073709552e+19",
      "utf8_hex": "312e38343436373434303733373039353532652b3139",
      "encoded_bytes": 22,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "43f0000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-integer-overflow-then-decimal",
    "input": {
      "representation": "text",
      "owned_input": "184467440737095516160.5",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1.844674407370955e+20",
      "utf8_hex": "312e383434363734343037333730393535652b3230",
      "encoded_bytes": 21,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "4424000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-unsafe-integer-decimal",
    "input": {
      "representation": "text",
      "owned_input": "9007199254740993.0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "9007199254740994.0",
      "utf8_hex": "393030373139393235343734303939342e30",
      "encoded_bytes": 18,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "4340000000000001"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-max-finite-decimal",
    "input": {
      "representation": "text",
      "owned_input": "1.7976931348623157e308",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1.7976931348623157e+308",
      "utf8_hex": "312e37393736393331333438363233313537652b333038",
      "encoded_bytes": 23,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "7fefffffffffffff"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-min-normal-decimal",
    "input": {
      "representation": "text",
      "owned_input": "2.2250738585072014e-308",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "2.2250738585072014e-308",
      "utf8_hex": "322e32323530373338353835303732303134652d333038",
      "encoded_bytes": 23,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "0010000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-min-subnormal",
    "input": {
      "representation": "text",
      "owned_input": "5e-324",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "5e-324",
      "utf8_hex": "35652d333234",
      "encoded_bytes": 6,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "0000000000000001"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-under-half-subnormal",
    "input": {
      "representation": "text",
      "owned_input": "2e-324",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "0.0",
      "utf8_hex": "302e30",
      "encoded_bytes": 3,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "0000000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-above-half-subnormal",
    "input": {
      "representation": "text",
      "owned_input": "3e-324",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "5e-324",
      "utf8_hex": "35652d333234",
      "encoded_bytes": 6,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "0000000000000001"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-negative-min-subnormal",
    "input": {
      "representation": "text",
      "owned_input": "-5e-324",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-5e-324",
      "utf8_hex": "2d35652d333234",
      "encoded_bytes": 7,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "8000000000000001"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-deep-underflow",
    "input": {
      "representation": "text",
      "owned_input": "1e-999",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "0.0",
      "utf8_hex": "302e30",
      "encoded_bytes": 3,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "0000000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-negative-deep-underflow",
    "input": {
      "representation": "text",
      "owned_input": "-1e-999",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-0.0",
      "utf8_hex": "2d302e30",
      "encoded_bytes": 4,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "8000000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-power-positive",
    "input": {
      "representation": "text",
      "owned_input": "1e23",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "1e+23",
      "utf8_hex": "31652b3233",
      "encoded_bytes": 5,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "44b52d02c7e14af6"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-large-cast-tie-even-down",
    "input": {
      "representation": "text",
      "owned_input": "9007199254740993e0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "9007199254740992.0",
      "utf8_hex": "393030373139393235343734303939322e30",
      "encoded_bytes": 18,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "4340000000000000"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-large-cast-tie-even-up",
    "input": {
      "representation": "text",
      "owned_input": "9007199254740995e0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "9007199254740996.0",
      "utf8_hex": "393030373139393235343734303939362e30",
      "encoded_bytes": 18,
      "fresh_owned_output": true,
      "source_number": {
        "class": "f64",
        "bits": "4340000000000002"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-integer-zero",
    "input": {
      "representation": "text",
      "owned_input": "0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "0",
      "utf8_hex": "30",
      "encoded_bytes": 1,
      "fresh_owned_output": true,
      "source_number": {
        "class": "u64",
        "decimal": "0"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-i64-max-as-u64",
    "input": {
      "representation": "text",
      "owned_input": "9223372036854775807",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "9223372036854775807",
      "utf8_hex": "39323233333732303336383534373735383037",
      "encoded_bytes": 19,
      "fresh_owned_output": true,
      "source_number": {
        "class": "u64",
        "decimal": "9223372036854775807"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-positive-over-i64",
    "input": {
      "representation": "text",
      "owned_input": "9223372036854775808",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "9223372036854775808",
      "utf8_hex": "39323233333732303336383534373735383038",
      "encoded_bytes": 19,
      "fresh_owned_output": true,
      "source_number": {
        "class": "u64",
        "decimal": "9223372036854775808"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-negative-i64-neighbor",
    "input": {
      "representation": "text",
      "owned_input": "-9223372036854775807",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-9223372036854775807",
      "utf8_hex": "2d39323233333732303336383534373735383037",
      "encoded_bytes": 20,
      "fresh_owned_output": true,
      "source_number": {
        "class": "i64",
        "decimal": "-9223372036854775807"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-numeric-negative-safe-integer",
    "input": {
      "representation": "text",
      "owned_input": "-9007199254740993",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "-9007199254740993",
      "utf8_hex": "2d39303037313939323534373430393933",
      "encoded_bytes": 17,
      "fresh_owned_output": true,
      "source_number": {
        "class": "i64",
        "decimal": "-9007199254740993"
      }
    },
    "source_basis": "Accepted pre-code number source-class literal + accepted scalar renderer integer/IEEE-shortest formatting source policy; output independently literal, no candidate execution"
  },
  {
    "case_id": "serialize-negative-zero",
    "input": {
      "representation": "text",
      "owned_input": "[-0,1,1.0,1e0]",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "[-0.0,1,1.0,1.0]",
      "utf8_hex": "5b2d302e302c312c312e302c312e305d",
      "encoded_bytes": 16,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-compact-lf",
    "input": {
      "representation": "text",
      "owned_input": "{\"b\":1,\"a\":2}",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "utf8": "{\"a\":2,\"b\":1}\n",
      "utf8_hex": "7b2261223a322c2262223a317d0a",
      "encoded_bytes": 14,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-compact-no-lf",
    "input": {
      "representation": "text",
      "owned_input": "{}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "{}",
      "utf8_hex": "7b7d",
      "encoded_bytes": 2,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-large-integer",
    "input": {
      "representation": "text",
      "owned_input": "9007199254740993",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "9007199254740993",
      "utf8_hex": "39303037313939323534373430393933",
      "encoded_bytes": 16,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-escaped-string",
    "input": {
      "representation": "text",
      "owned_input": "\"a\\n\\\"\\\\\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "utf8": "\"a\\n\\\"\\\\\"",
      "utf8_hex": "22615c6e5c225c5c22",
      "encoded_bytes": 9,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-lf-null",
    "input": {
      "representation": "text",
      "owned_input": "null",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "utf8": "null\n",
      "utf8_hex": "6e756c6c0a",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-lf-string",
    "input": {
      "representation": "text",
      "owned_input": "\"\\n\"",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "utf8": "\"\\n\"\n",
      "utf8_hex": "225c6e220a",
      "encoded_bytes": 5,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-lf-existing-string-newline",
    "input": {
      "representation": "text",
      "owned_input": "\"a\\n\"",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "utf8": "\"a\\n\"\n",
      "utf8_hex": "22615c6e220a",
      "encoded_bytes": 6,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-lf-nested",
    "input": {
      "representation": "text",
      "owned_input": "[{},[]]",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "utf8": "[{},[]]\n",
      "utf8_hex": "5b7b7d2c5b5d5d0a",
      "encoded_bytes": 8,
      "fresh_owned_output": true
    },
    "source_basis": "serde_json ser.rs ESCAPE/Value::serialize and accepted default BTreeMap semantics"
  },
  {
    "case_id": "serialize-foreign-handle",
    "input": {
      "harness": "Construct A serializer from A codec/token; parse [1] with B; encode B root with valid compact policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-foreign-child",
    "input": {
      "harness": "Construct A serializer; encode child handle obtained from B original reader on B [1]"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-handle-proxy",
    "input": {
      "harness": "Throwing all-trap Proxy object as handle, valid compact policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-handle-revoked-proxy",
    "input": {
      "harness": "Create/revoke Proxy then encode proxy as foreign handle; no property operation allowed"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-forged-ast",
    "input": {
      "harness": "Caller object mimics number node with getter/toJSON/valueOf/Symbol.toPrimitive traps"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-handle-null",
    "input": {
      "harness": "null handle; valid policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-handle-number",
    "input": {
      "harness": "1 handle; valid policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-handle-symbol",
    "input": {
      "harness": "Symbol handle; valid policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-handle-bigint",
    "input": {
      "harness": "1n handle; valid policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-handle-function",
    "input": {
      "harness": "throwing caller function handle; never invoke"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-codec-proxy",
    "input": {
      "harness": "createCanonicalJsonSerializer receives throwing Proxy codec and authentic A token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-codec-revoked-proxy",
    "input": {
      "harness": "constructor revoked Proxy codec and authentic token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-token-proxy",
    "input": {
      "harness": "constructor authentic A codec and throwing Proxy token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-token-revoked-proxy",
    "input": {
      "harness": "constructor authentic A codec and revoked Proxy token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-token-cross-factory",
    "input": {
      "harness": "constructor A codec plus B token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-token-forged",
    "input": {
      "harness": "constructor A codec plus empty caller object token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-codec-getter-forged",
    "input": {
      "harness": "constructor object with getter parse/read/capture and coercion traps plus authentic token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-codec-null",
    "input": {
      "harness": "constructor null codec with authentic token"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-reader-function-injection",
    "input": {
      "harness": "constructor receives arbitrary caller read function as codec and arbitrary callback as token; no invoke"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-invalid-profile",
    "input": {
      "harness": "Encode authentic {} with foundation_ordered_json"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-pretty-profile",
    "input": {
      "harness": "Encode authentic {} with pretty_json"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-empty-profile",
    "input": {
      "harness": "Encode authentic {} with empty string"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-undefined-profile",
    "input": {
      "harness": "Encode authentic {} with undefined"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-policy-proxy",
    "input": {
      "harness": "Encode authentic {} with throwing Proxy policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-policy-revoked-proxy",
    "input": {
      "harness": "Encode authentic {} with revoked Proxy policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-policy-coercion",
    "input": {
      "harness": "Encode authentic {} with accessor/toString/valueOf/Symbol.toPrimitive traps"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-policy-number",
    "input": {
      "harness": "Encode authentic {} with1 policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-policy-overlong",
    "input": {
      "harness": "Encode authentic {} with primitive compact suffixASCIIa1048577; reject before graph walk"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-typed-array-handle",
    "input": {
      "harness": "Encode Uint8Array caller handle with valid policy"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-reader-object-injection",
    "input": {
      "harness": "Pass captured reader object as constructor codec; never read read property"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0,
      "partial_output_published": false
    },
    "source_basis": "Private primitive-policy/per-factory membership gates and bounded full preflight; not serde public rejection parity"
  },
  {
    "case_id": "serialize-output-owned",
    "input": {
      "owned_input": "[1]",
      "harness": "Encode twice; mutate first output byte0 to0 and contents; retain second bytes then encode third; verify all distinct ArrayBuffers and byte views"
    },
    "expected": {
      "first_before_utf8": "[1]",
      "second_utf8": "[1]",
      "third_utf8": "[1]",
      "same_buffer": false,
      "same_view": false,
      "input_handle_unchanged": true
    },
    "source_basis": "Private fresh owned bytes, immutable AST"
  },
  {
    "case_id": "serialize-original-reader-capture",
    "input": {
      "owned_input": "{\"b\":1,\"a\":2}",
      "harness": "Capture serializer from authentic pair once; attempt Reflect.set on frozen codec/read binding and local reader-variable substitute trappingfunction; encode original handle"
    },
    "expected": {
      "utf8": "{\"a\":2,\"b\":1}",
      "substitution_accepted": false,
      "traps": 0
    },
    "source_basis": "captureExactJsonValueReader authentic WM and original frozen reader once, no caller reprovide"
  },
  {
    "case_id": "serialize-same-factory-child",
    "input": {
      "owned_input": "[1,2]",
      "harness": "Original samefactory reader obtains first child handle; encode child"
    },
    "expected": {
      "utf8": "1"
    },
    "source_basis": "Any authentic samefactory child is Value, no root-only invented restriction"
  },
  {
    "case_id": "serialize-pure-scope-no-authority",
    "input": {
      "owned_input": "{\"a\":1}",
      "harness": "Close unrelated original operation Scope; encode authentic value then operation adapter refuses delivery"
    },
    "expected": {
      "utf8": "{\"a\":1}",
      "source_authorized": false,
      "delivery_allowed": false
    },
    "source_basis": "Pure authenticity does not confer source grant or bind Effect Scope; operation lifecycle separately owns authority"
  },
  {
    "case_id": "serialize-reused-handle-policy-independent",
    "input": {
      "owned_input": "\"a\\n\"",
      "harness": "Encode same handle compact then compact_lf then compact"
    },
    "expected": {
      "utf8_sequence": [
        "\"a\\n\"",
        "\"a\\n\"\n",
        "\"a\\n\""
      ],
      "all_buffers_distinct": true
    },
    "source_basis": "Policy no mutation/implicit newline state"
  },
  {
    "case_id": "serialize-bound-compact-one-below",
    "input": {
      "harness": "bounded_array_numeric_output",
      "repeat_token": "1e15",
      "repeat_count": 55188,
      "tail_json": "0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "complete_encoded_bytes": 1048575,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "output_recipe": {
        "prefix": "[",
        "repeated": "1000000000000000.0,",
        "repeat_count": 55188,
        "tail": "0]"
      },
      "fresh_owned_output": true
    },
    "source_basis": "1e15 exact source F64 and shortest fixed18-byte lexeme; array 19*N+1 base then tailcomma(1+tailbytes), LF one byte; private cap not public equivalence"
  },
  {
    "case_id": "serialize-bound-compact-at",
    "input": {
      "harness": "bounded_array_numeric_output",
      "repeat_token": "1e15",
      "repeat_count": 55188,
      "tail_json": "\"\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "complete_encoded_bytes": 1048576,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "output_recipe": {
        "prefix": "[",
        "repeated": "1000000000000000.0,",
        "repeat_count": 55188,
        "tail": "\"\"]"
      },
      "fresh_owned_output": true
    },
    "source_basis": "1e15 exact source F64 and shortest fixed18-byte lexeme; array 19*N+1 base then tailcomma(1+tailbytes), LF one byte; private cap not public equivalence"
  },
  {
    "case_id": "serialize-bound-compact-over",
    "input": {
      "harness": "bounded_array_numeric_output",
      "repeat_token": "1e15",
      "repeat_count": 55188,
      "tail_json": "\"a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "complete_encoded_bytes": 1048577,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "error": "invalid_json_value"
    },
    "source_basis": "1e15 exact source F64 and shortest fixed18-byte lexeme; array 19*N+1 base then tailcomma(1+tailbytes), LF one byte; private cap not public equivalence"
  },
  {
    "case_id": "serialize-bound-lf-at",
    "input": {
      "harness": "bounded_array_numeric_output",
      "repeat_token": "1e15",
      "repeat_count": 55188,
      "tail_json": "0",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "complete_encoded_bytes": 1048576,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "output_recipe": {
        "prefix": "[",
        "repeated": "1000000000000000.0,",
        "repeat_count": 55188,
        "tail": "0]\n"
      },
      "fresh_owned_output": true
    },
    "source_basis": "1e15 exact source F64 and shortest fixed18-byte lexeme; array 19*N+1 base then tailcomma(1+tailbytes), LF one byte; private cap not public equivalence"
  },
  {
    "case_id": "serialize-bound-lf-over",
    "input": {
      "harness": "bounded_array_numeric_output",
      "repeat_token": "1e15",
      "repeat_count": 55188,
      "tail_json": "\"\"",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "complete_encoded_bytes": 1048577,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "error": "invalid_json_value"
    },
    "source_basis": "1e15 exact source F64 and shortest fixed18-byte lexeme; array 19*N+1 base then tailcomma(1+tailbytes), LF one byte; private cap not public equivalence"
  },
  {
    "case_id": "serialize-bound-escaped-at",
    "input": {
      "harness": "bounded_array_escaped_output",
      "repeat_token": "1e15",
      "repeat_count": 55187,
      "escaped_string_json": "\"\\u0000\\n\\\"\\\\é\"",
      "tail_json": "null",
      "policy": "serde_value_compact"
    },
    "expected": {
      "complete_encoded_bytes": 1048576,
      "decoded_last_string_bytes": 6,
      "escaped_string_encoded_bytes": 16,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "output_recipe": {
        "prefix": "[",
        "repeated": "1000000000000000.0,",
        "repeat_count": 55187,
        "tail": "\"\\u0000\\n\\\"\\\\é\",null]"
      },
      "fresh_owned_output": true
    },
    "source_basis": "Private preflight counts syntax2+NUL6+LF2+quote2+backslash2+éUTF8two=16; base19*55187+1=1048554, comma+string17 then comma+null5=1048576"
  },
  {
    "case_id": "serialize-bound-escaped-lf-over",
    "input": {
      "harness": "bounded_array_escaped_output",
      "repeat_token": "1e15",
      "repeat_count": 55187,
      "escaped_string_json": "\"\\u0000\\n\\\"\\\\é\"",
      "tail_json": "null",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "complete_encoded_bytes": 1048577,
      "decoded_last_string_bytes": 6,
      "escaped_string_encoded_bytes": 16,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "error": "invalid_json_value"
    },
    "source_basis": "Private preflight counts syntax2+NUL6+LF2+quote2+backslash2+éUTF8two=16; base19*55187+1=1048554, comma+string17 then comma+null5=1048576"
  },
  {
    "case_id": "serialize-bound-escaped-over",
    "input": {
      "harness": "bounded_array_escaped_output",
      "repeat_token": "1e15",
      "repeat_count": 55187,
      "escaped_string_json": "\"\\u0000\\n\\\"\\\\é\"",
      "tail_json": "false",
      "policy": "serde_value_compact"
    },
    "expected": {
      "complete_encoded_bytes": 1048577,
      "decoded_last_string_bytes": 6,
      "escaped_string_encoded_bytes": 16,
      "numeric_lexeme": "1000000000000000.0",
      "partial_output_published": false,
      "error": "invalid_json_value"
    },
    "source_basis": "Private preflight counts syntax2+NUL6+LF2+quote2+backslash2+éUTF8two=16; base19*55187+1=1048554, comma+string17 then comma+null5=1048576"
  },
  {
    "case_id": "serialize-bound-max-nodes",
    "input": {
      "harness": "array_nulls",
      "count": 65535,
      "policy": "serde_value_compact"
    },
    "expected": {
      "encoded_bytes": 327676,
      "output_recipe": {
        "prefix": "[",
        "repeated": "null,",
        "repeat_count": 65534,
        "tail": "null]"
      },
      "nodes": 65536,
      "fresh_owned_output": true
    },
    "source_basis": "Accepted Value private parser admission and source UTF8/escape size, complete numeric/string/output budgets retained"
  },
  {
    "case_id": "serialize-bound-max-depth",
    "input": {
      "harness": "nested_arrays",
      "count": 127,
      "inner_json": "null",
      "policy": "serde_value_compact"
    },
    "expected": {
      "encoded_bytes": 258,
      "output_recipe": {
        "opening_brackets": 127,
        "inner": "null",
        "closing_brackets": 127
      },
      "fresh_owned_output": true
    },
    "source_basis": "Accepted Value private parser admission and source UTF8/escape size, complete numeric/string/output budgets retained"
  },
  {
    "case_id": "serialize-bound-max-string",
    "input": {
      "harness": "quoted_ascii",
      "char": "a",
      "count": 262144,
      "policy": "serde_value_compact"
    },
    "expected": {
      "encoded_bytes": 262146,
      "output_recipe": {
        "quote": true,
        "char": "a",
        "repeat_count": 262144
      },
      "fresh_owned_output": true
    },
    "source_basis": "Accepted Value private parser admission and source UTF8/escape size, complete numeric/string/output budgets retained"
  },
  {
    "case_id": "serialize-bound-expanded-string",
    "input": {
      "harness": "quoted_escaped_short_control",
      "escape": "\\n",
      "count": 262144,
      "policy": "serde_value_compact"
    },
    "expected": {
      "encoded_bytes": 524290,
      "output_recipe": {
        "quote": true,
        "repeated": "\\n",
        "repeat_count": 262144
      },
      "fresh_owned_output": true
    },
    "source_basis": "Accepted Value private parser admission and source UTF8/escape size, complete numeric/string/output budgets retained"
  },
  {
    "case_id": "serialize-bound-utf8-string",
    "input": {
      "harness": "quoted_unicode",
      "char": "é",
      "count": 131072,
      "policy": "serde_value_compact"
    },
    "expected": {
      "encoded_bytes": 262146,
      "output_recipe": {
        "quote": true,
        "char": "é",
        "repeat_count": 131072
      },
      "fresh_owned_output": true
    },
    "source_basis": "Accepted Value private parser admission and source UTF8/escape size, complete numeric/string/output budgets retained"
  },
  {
    "case_id": "serialize-parser-rejection-lone-high",
    "input": {
      "representation": "text",
      "owned_input": "\"\\ud800\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "parse_error": "invalid_json_value",
      "encode_calls": 0,
      "partial_output_published": false
    },
    "source_basis": "Accepted Value parser primary scalar/first RawValue semantics, no arbitrary caller AST fallback"
  },
  {
    "case_id": "serialize-parser-rejection-lone-low",
    "input": {
      "representation": "text",
      "owned_input": "\"\\udc00\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "parse_error": "invalid_json_value",
      "encode_calls": 0,
      "partial_output_published": false
    },
    "source_basis": "Accepted Value parser primary scalar/first RawValue semantics, no arbitrary caller AST fallback"
  },
  {
    "case_id": "serialize-parser-rejection-wrong-pair",
    "input": {
      "representation": "text",
      "owned_input": "\"\\ud800a\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "parse_error": "invalid_json_value",
      "encode_calls": 0,
      "partial_output_published": false
    },
    "source_basis": "Accepted Value parser primary scalar/first RawValue semantics, no arbitrary caller AST fallback"
  },
  {
    "case_id": "serialize-parser-rejection-raw-invalid",
    "input": {
      "representation": "text",
      "owned_input": "{\"$serde_json::private::RawValue\":\"x\"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "parse_error": "invalid_json_value",
      "encode_calls": 0,
      "partial_output_published": false
    },
    "source_basis": "Accepted Value parser primary scalar/first RawValue semantics, no arbitrary caller AST fallback"
  },
  {
    "case_id": "serialize-parser-rejection-raw-nonstring",
    "input": {
      "representation": "text",
      "owned_input": "{\"$serde_json::private::RawValue\":1}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "parse_error": "invalid_json_value",
      "encode_calls": 0,
      "partial_output_published": false
    },
    "source_basis": "Accepted Value parser primary scalar/first RawValue semantics, no arbitrary caller AST fallback"
  },
  {
    "case_id": "serialize-parser-rejection-raw-trailing-member",
    "input": {
      "representation": "text",
      "owned_input": "{\"$serde_json::private::RawValue\":\"null\",\"a\":1}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "parse_error": "invalid_json_value",
      "encode_calls": 0,
      "partial_output_published": false
    },
    "source_basis": "Accepted Value parser primary scalar/first RawValue semantics, no arbitrary caller AST fallback"
  },
  {
    "case_id": "serialize-parser-rejection-numeric-overflow",
    "input": {
      "representation": "text",
      "owned_input": "1e9999",
      "policy": "serde_value_compact"
    },
    "expected": {
      "parse_error": "invalid_json_value",
      "encode_calls": 0,
      "partial_output_published": false
    },
    "source_basis": "Accepted Value parser primary scalar/first RawValue semantics, no arbitrary caller AST fallback"
  }
] as const;

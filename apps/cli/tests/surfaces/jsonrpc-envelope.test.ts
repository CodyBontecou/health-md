/** Private semantic-port stimuli. Source-only until independent final review; no public codec parity. */
import assert from "node:assert/strict";
import test from "node:test";
import * as Effect from "effect/Effect";
import * as Exit from "effect/Exit";
import * as Scope from "effect/Scope";
import * as Deferred from "effect/Deferred";
import * as Fiber from "effect/Fiber";
import { createRpcEnvelope, type SourceValue, type SourceNumber, type FixedFailure, type TrustedFactoryInputs, type RpcEnvelope, type OwnedSession, type CodecIssuer, type OwnedInspectionOutcome, type OwnedFrame, type OwnedOutput, type OwnedParsed, type OwnedSpan, type OwnedJson, type AuthorizedRequestView, type OperationIssuer, type InspectionMetadata, type OwnedOutputView } from "../../src/surfaces/jsonrpc-envelope.js";
import { rpcEnvelopeFixture } from "./jsonrpc-envelope-vectors.js";
interface FrameInput { readonly frame_utf8: string; readonly frame_sha256: string; readonly disposition: "parsed" | "source_parse_error"; readonly primitive_metadata_wire: string | null; readonly source_value_wire: string | null }
// Independently reviewed85 raw descriptor input rows; no expected envelope bytes or case IDs.
const frameInputs: readonly FrameInput[] = [
  {
    "frame_utf8": "\"x\"",
    "frame_sha256": "ba2df4903a2c14e86dc3bcca58911b44ac1d2514b7227bf6eb08cfb978f55a1b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":false,\"version2\":false,\"id\":{\"present\":false},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "\"x\""
  },
  {
    "frame_utf8": "1",
    "frame_sha256": "6b86b273ff34fce19d6b804eff5a3f5747ada4eaa22f1d49c01e52ddb7875b4b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":false,\"version2\":false,\"id\":{\"present\":false},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}"
  },
  {
    "frame_utf8": "[]",
    "frame_sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":false,\"version2\":false,\"id\":{\"present\":false},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "[]"
  },
  {
    "frame_utf8": "null",
    "frame_sha256": "74234e98afe7498fb5daf1f36ac2d78acc339464f950703b8c019892f982b90b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":false,\"version2\":false,\"id\":{\"present\":false},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "null"
  },
  {
    "frame_utf8": "{",
    "frame_sha256": "021fb596db81e6d02bf3d2586ee3981fe519f275c0ac9ca76bbcf2ebb4097d96",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"id\":1,\"method\":\"ping\"}",
    "frame_sha256": "318793467a85e516b0df22beaccebc73fa34ade530c460230f8e69a390b09c00",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":false,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"1.0\",\"id\":1,\"method\":\"ping\"}",
    "frame_sha256": "30e040b69e1fb3ca6fd23a4799eb191e1fff7ae50d00505b6abeee53cb245a8f",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":false,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"1.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"1.0\",\"id\":1e9999,\"method\":\"ping\"}",
    "frame_sha256": "7bec4c93ad6c9d48a5e0140ab0811430783e852dd2ada7139c37f5ebee6b4c31",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"1.0\",\"method\":\"ping\"}",
    "frame_sha256": "9c9f7cbf82ebcd2cab09de58f49a50a26a73cff05f9b3aa59c796d40ceb79fe8",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":false,\"id\":{\"present\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"jsonrpc\",\"1.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\",\"method\":\"ping\"}",
    "frame_sha256": "9e8551db824accbe62597bc5a270b5903b099b24dc562f71d1b8504f9478b869",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"0\",\"method\":\"ping\"}",
    "frame_sha256": "21c89f51f95a321c45a4942ebd340a40761a00dbd3a321d38ea73a6bbecc7835",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"0\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"0\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"1\",\"method\":\"ping\"}",
    "frame_sha256": "6357629b48bcb9029db19b927d364bdd2e6fcda54a1bb7178a80dac69bf428ca",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"1\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"1\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\\b\\f\\n\\r\\t\\u0001\\\"\\\\/\",\"method\":\"ping\"}",
    "frame_sha256": "cc67fb6efeb24cb3859c2cbb266912b7039639206d45cbb87595f9c4a3f924c0",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\\\b\\\\f\\\\n\\\\r\\\\t\\\\u0001\\\\\\\"\\\\\\\\/\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\\b\\f\\n\\r\\t\\u0001\\\"\\\\/\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\",\"method\":\"ping\"}",
    "frame_sha256": "fab830af2b74ff2138ee6131f0e59b7875e92e1952a86fdcc45cc2c5a6ca2ace",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\",\"method\":\"ping\"}",
    "frame_sha256": "2549ca2c5d93e6a0ad82855a938f02b1673f4e1ca93320b3c473c9a4d77343b3",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\\u0000\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\\u0061\",\"method\":\"ping\"}",
    "frame_sha256": "e986eeda07e71a37d3df7bfe66c078121577c14a4e286bf7e1f09ba628288e3b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"a\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"a\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\\ud800\",\"method\":\"ping\"}",
    "frame_sha256": "9c98b6412b12ba5fadc645994ed3298b8cf62c6ac0a004eee39dcfe4e96d1f49",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\\ud83d\\ude00\",\"method\":\"ping\"}",
    "frame_sha256": "49332ad2274d7b8c9ffeb163d96977df4c6dba8ed6eb87b03e01fb30c1bfaffe",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\ud83d\\ude00\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\\ud83d\\ude00\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"a\",\"method\":\"ping\"}",
    "frame_sha256": "3c01f60a430830ffa731761f3e9a477aa9b4c0913546e643a2c3dd70e333fe88",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"a\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"a\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"a\\/b\",\"method\":\"ping\"}",
    "frame_sha256": "17ce8554f70fa90cb76a18bed48f6b48121e16874a1161f3d22178f7c0e9e466",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"a/b\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"a/b\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"method\":\"ping\"}",
    "frame_sha256": "d0648e64597408f0e26133bcf8c5d8aee89c47872630443c8a4061e50dbb852b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\",\"method\":\"ping\"}",
    "frame_sha256": "d5378e20de0177b269537987e02eba37929ec26829f0baf7fd332cce72220384",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"x}",
    "frame_sha256": "f3197df4b0eb42f8f8ebc6e9a97f95e18aa62b93820c8ba04b9fc18ee9a85f72",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\u00e9\ud83d\ude00\",\"method\":\"ping\"}",
    "frame_sha256": "0d8e0fb370aac12664026fddd5af78ad1fa0871a1375214c513b581cee007e40",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\u00e9\\ud83d\\ude00\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\\u00e9\\ud83d\\ude00\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\",\"method\":\"ping\"}",
    "frame_sha256": "a3dc4b1447ee0bd6ae4129f9a474bfddd10da3cdb35d0ee6b35fe5fcc77ec1d4",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":\"\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\ud83d\ude00\",\"method\":\"ping\"}",
    "frame_sha256": "183130244ebe540d618c73bdbda3f5fdf811104eed404c77e5b8d469c64d452e",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"string\",\"canonicalEncoded\":\"\\\"\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\\"\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",\"\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\\ud83d\\ude00\"],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":-0,\"method\":\"ping\"}",
    "frame_sha256": "7a21b234079cfcaa8007b28c76ad368ff14992672fdcc32037bc741dafdc43cd",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"binary64\",\"canonicalEncoded\":\"-0.0\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"binary64\",\"bits\":\"8000000000000000\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":-9223372036854775808,\"method\":\"ping\"}",
    "frame_sha256": "9388101fce588185b90bad861c4f6ed805d35c3afee8522db870aab18b38d200",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"signed_integer\",\"canonicalEncoded\":\"-9223372036854775808\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"signed_integer\",\"decimal\":\"-9223372036854775808\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":0,\"method\":\"ping\"}",
    "frame_sha256": "63258bd54cb8842b00c7622080a38ce5e37620b23cf5b7cba0d13360ebd126bc",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"0\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"0\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":01,\"method\":\"ping\"}",
    "frame_sha256": "3009a000ee7e5eb3a78dfc02c4cfe29bca41e03023fa434645eb882949512264",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"bad\",\"m\\u0065thod\":\"ping\"}",
    "frame_sha256": "e05987f58d9032799a9de43db78dc727ff24164bfcc332c7735f41f8dc1f8b5d",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"bad\",\"method\":\"ping\"}",
    "frame_sha256": "95bec870c5c0577ce29f02e8518e5551f3ebe1a3754ca24ee1f97edb0d9198bd",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2024-11-05\"}}",
    "frame_sha256": "41060ff2258f6b294bf1a2bb1d1b8fdba5119149e33952b12f943d6fc006713a",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"initialize\",\"params\":{\"start\":55,\"end\":87},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"initialize\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"protocolVersion\",\"2024-11-05\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-03-26\"}}",
    "frame_sha256": "a75e4d16327aa10c2ebeb43f93612324ce7cabfb3f0f6784952f96873c66b069",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"initialize\",\"params\":{\"start\":55,\"end\":87},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"initialize\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"protocolVersion\",\"2025-03-26\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-06-18\"}}",
    "frame_sha256": "3ca0d8dd4a286f7109c062eec44771b06ce3a33929a79d70eddc5f97f9e5727f",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"initialize\",\"params\":{\"start\":55,\"end\":87},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"initialize\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"protocolVersion\",\"2025-06-18\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"extensions\":{\"io.modelcontextprotocol/ui\":{\"mimeTypes\":[\"text/html\"]}}}}}",
    "frame_sha256": "dddd31a5f2ab67d4ec775d0937fe6e99146e0ec543d7fa53e07fbbbc864d0097",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"initialize\",\"params\":{\"start\":55,\"end\":176},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"initialize\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"capabilities\",{\"kind\":\"object\",\"entries\":[[\"extensions\",{\"kind\":\"object\",\"entries\":[[\"io.modelcontextprotocol/ui\",{\"kind\":\"object\",\"entries\":[[\"mimeTypes\",[\"text/html\"]]]}]]}]]}],[\"protocolVersion\",\"2025-11-25\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"extensions\":{\"io.modelcontextprotocol/ui\":{\"mimeTypes\":[\"text/html;profile=mcp-app\"]}}}}}",
    "frame_sha256": "884b84f1c4a41d6eb6ff4831900e03c8f4e47c7edda0482c1a12df41d6976ef7",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"initialize\",\"params\":{\"start\":55,\"end\":192},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"initialize\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"capabilities\",{\"kind\":\"object\",\"entries\":[[\"extensions\",{\"kind\":\"object\",\"entries\":[[\"io.modelcontextprotocol/ui\",{\"kind\":\"object\",\"entries\":[[\"mimeTypes\",[\"text/html;profile=mcp-app\"]]]}]]}]]}],[\"protocolVersion\",\"2025-11-25\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\"}}",
    "frame_sha256": "3c4747582017c8408e921a74764d63d6f23960526120406792684416f4cef7a5",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"initialize\",\"params\":{\"start\":55,\"end\":87},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"initialize\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"protocolVersion\",\"2025-11-25\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2026-07-28\"}}",
    "frame_sha256": "1b2ead19b241f426e26aa1432a0e0670615374f30cae372d10ec02523838fa8d",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"initialize\",\"params\":{\"start\":55,\"end\":87},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"initialize\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"protocolVersion\",\"2026-07-28\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"extra\":true}",
    "frame_sha256": "68f705473449996e9dcdb38871b50ef6351a8d516ee0e78a13492e61de129068",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"extra\",true],[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"ignored\":1e9999}",
    "frame_sha256": "9d0a08359da524b51bf260b59aac6aae4d21ad5650bf40469249dbf49b134992",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"outer\":{\"id\":false,\"method\":[],\"nested\":[null,{\"id\":1.0}]}}",
    "frame_sha256": "f284d0bbb1be8b3ce93d31d58dc40df6ca68eb8ce167cfe36e9c4fa8c7adec36",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"],[\"outer\",{\"kind\":\"object\",\"entries\":[[\"id\",false],[\"method\",[]],[\"nested\",[null,{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"binary64\",\"bits\":\"3ff0000000000000\"}]]}]]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":null}",
    "frame_sha256": "45365784472ac279177354202825f343328e2070ca60606c28f97b2fb589b87c",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":{\"start\":49,\"end\":53},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"],[\"params\",null]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"private\":true}}",
    "frame_sha256": "743833e2e4db9854996e58d9c36f0d0b09e138885827de654cef7135c7fceb02",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":{\"start\":49,\"end\":65},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"private\",true]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\",\"params\":{\"unused\":1e9999}}",
    "frame_sha256": "39df6aaa8b1be5a4a86e36adbcac12605b3839d7335f40a09605af8efe816e2f",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
    "frame_sha256": "98e0961a7c1232f08d2f2187d13c4a1a22a0641e00e5dec0eca645d646077fab",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}x",
    "frame_sha256": "26a658a237df45bb351ada58c7f057b8e928d2009353e48e95977f757e5d24c3",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"private_method\"}",
    "frame_sha256": "05483e6163f33bb3e146d6dc6b814c5e0f9596c8e4a5a0bfa9831195217d0b99",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"private_method\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"private_method\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"resources/list\"}",
    "frame_sha256": "77fab4689d69b39fbd2916d2ac1176184bc6fa76bbf97017ed1269aa80604231",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"resources/list\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"resources/list\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"_meta\":{\"progressToken\":7}}}",
    "frame_sha256": "3f03553eb3eddbd20666ea84fbb9d9141370b49211aed4628b9802d307ebdd79",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":109},\"paramsDefaulted\":false,\"progressToken\":{\"start\":106,\"end\":107}}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"unsigned_integer\",\"decimal\":\"7\"}]]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\"}}}",
    "frame_sha256": "9e4059ffa9fe5567b357e056c1ff4375a21f64ff58aa0392629004f99ce7450f",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":257},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":255}}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",\"\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\\u0000\"]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}}}",
    "frame_sha256": "05509c677fc53f42c161d1b1a2c087e8795b891f1bd9c72be0c04a5f7ad573f7",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":253},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":251}}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"}}}",
    "frame_sha256": "318e4786e97d1a4e06a195a07492f4775e0520cc0c259d1625ea6feb4231316b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":254},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",\"xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx\"]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":1.0}}}",
    "frame_sha256": "feb369fbd7ea6a1dee3e930196f07743bdae380908749539d60ccb8d08faae6b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":126},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"binary64\",\"bits\":\"3ff0000000000000\"}]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
    "frame_sha256": "d4c84ec7ec8d01340ac4ebd35ff74ab6315d4c35b1944f5cf59beebc907b4be3",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":124},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":122}}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"unsigned_integer\",\"decimal\":\"7\"}]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":9223372036854775807}}}",
    "frame_sha256": "bcb2803824634961cc502f459ad6838143860a06c348997492d29f7e1ae59ddb",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":142},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":140}}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"unsigned_integer\",\"decimal\":\"9223372036854775807\"}]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{}}}",
    "frame_sha256": "0a12f99465f9da5499212b24414c255abd47342c3ccfa42649712b91e0921171",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":96},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
    "frame_sha256": "4f5f644e1303128ac2f319dbc461b236927b8ccf66eff11aaf470e3a6ac32bcb",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":81},\"paramsDefaulted\":false,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"unknown\"}",
    "frame_sha256": "f73ab2e1a60df1722d88d0cd25fe408c3c7c5fb2270e39d4342a9f16493e95a8",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"unknown\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"unknown\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1.0,\"method\":\"ping\"}",
    "frame_sha256": "f1fa1995107bc96a466f44ea747d1c8e9e70dbd0ac0d368f1ca29ae22fa34e3b",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"binary64\",\"canonicalEncoded\":\"1.0\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"binary64\",\"bits\":\"3ff0000000000000\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1.0}",
    "frame_sha256": "eff97e09366cf4b6d22bf57a44f1e5302f993c1e0604a14d5dc79f8ee1d6a16d",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"binary64\",\"canonicalEncoded\":\"1.0\",\"validI64OrString\":false},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"binary64\",\"bits\":\"3ff0000000000000\"}],[\"jsonrpc\",\"2.0\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1.5,\"method\":\"ping\"}",
    "frame_sha256": "b1f281fe0ba56eabdf3339893975441d007bd3dda0ae2ff7ea178f20174b6b33",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"binary64\",\"canonicalEncoded\":\"1.5\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"binary64\",\"bits\":\"3ff8000000000000\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1e0,\"method\":\"ping\"}",
    "frame_sha256": "2c0444e8ab2f31aefd30f115655c99a9be104da33dcbfc7127d3d70ac82c86ce",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"binary64\",\"canonicalEncoded\":\"1.0\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"binary64\",\"bits\":\"3ff0000000000000\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1e9999,\"method\":\"ping\"}",
    "frame_sha256": "0e8e0e8eb7bab65f8aa38aae2a713f2ea2a5e46e725956e425aa088f39e7c8d7",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1}",
    "frame_sha256": "fe46396dd3e614a8ae91a84e50c35548d8a5d7940d74dd33dc20c86f042329bc",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":2,\"\\u0069d\":1,\"method\":\"ping\"}",
    "frame_sha256": "8d6973e6358b7f898bfe2d9d53ddf6dbaffeae459e65c6f1664aacd7f8b48f88",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":2,\"id\":1,\"method\":\"ping\"}",
    "frame_sha256": "6e3a430e7be725b31e02e940dddfe3cf18bf61aa024caf2529db1ddf73376355",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":2,\"method\":\"ping\"}",
    "frame_sha256": "a94ce230590595554baa02bed4ba48a4e38457a3520821f06fd2b09c6b7e3137",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"2\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"2\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"_meta\":{\"progressToken\":\"wake-7\"}}}",
    "frame_sha256": "93099a2ccd760e58d66bc1861e73575281d1606926b8910bbcb015cedae71fb8",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"7\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":116},\"paramsDefaulted\":false,\"progressToken\":{\"start\":106,\"end\":114}}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"7\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",\"wake-7\"]]}],[\"name\",\"healthmd_status\"]]}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":9223372036854775807,\"method\":\"ping\"}",
    "frame_sha256": "387d73c5b3ce106f97b320497a1597267f4054218172067aeac18d43323fa861",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"9223372036854775807\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"9223372036854775807\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":9223372036854775808,\"method\":\"ping\"}",
    "frame_sha256": "deb4d11c5de2e6ffd03ddcf06ed19f0e8054f60c18ed2a98148b0b1d2fb7d346",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"9223372036854775808\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"9223372036854775808\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":NaN,\"method\":\"ping\"}",
    "frame_sha256": "211e1ea289a0d80beb690a7d035d91a200353a71bdb0df9e0ec999489e724038",
    "disposition": "source_parse_error",
    "primitive_metadata_wire": null,
    "source_value_wire": null
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":[],\"method\":\"ping\"}",
    "frame_sha256": "42569a4d611244546ee6deeae7418d696d144e45fd4c2416c5b8e71e2d92342e",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"invalid\",\"canonicalEncoded\":\"[]\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",[]],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":null,\"method\":\"ping\"}",
    "frame_sha256": "e3272aef75fdb322d32c28441cbdce29dbb53a17cad3e887c9843f94722fdaf1",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"invalid\",\"canonicalEncoded\":\"null\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",null],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":true,\"method\":\"ping\"}",
    "frame_sha256": "3c1e0ee35c6fc56937c65b8595a691a8b3375f8d4faa7eab8355e05222b2c414",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"invalid\",\"canonicalEncoded\":\"true\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",true],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":{\"z\":1,\"a\":2},\"method\":\"ping\"}",
    "frame_sha256": "6b231812faa032d4df1fc37c36e40958c0b071c80636f922a609d5ff47e471fc",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"invalid\",\"canonicalEncoded\":\"{\\\"a\\\":2,\\\"z\\\":1}\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"object\",\"entries\":[[\"a\",{\"kind\":\"unsigned_integer\",\"decimal\":\"2\"}],[\"z\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}]]}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":{\"\ud83d\ude00\":1,\"\ue000\":0},\"method\":\"ping\"}",
    "frame_sha256": "08765be2ee3da97b33a727843f9d11d63a5f9a2af119cae6e00d3f5b19b397ca",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"invalid\",\"canonicalEncoded\":\"{\\\"\\ue000\\\":0,\\\"\\ud83d\\ude00\\\":1}\",\"validI64OrString\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"object\",\"entries\":[[\"\\ue000\",{\"kind\":\"unsigned_integer\",\"decimal\":\"0\"}],[\"\\ud83d\\ude00\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}]]}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":{},\"method\":1}",
    "frame_sha256": "64e65ad3cdff2378b3be7c964a50e7f06755defd3fb52eddf1ad928f83e0d975",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"invalid\",\"canonicalEncoded\":\"{}\",\"validI64OrString\":false},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"object\",\"entries\":[]}],[\"jsonrpc\",\"2.0\"],[\"method\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"jsonrpc\":\"bad\",\"id\":1,\"method\":\"ping\"}",
    "frame_sha256": "8405beabd92f735a61ad4156909543e906bbb8b21b77b1293770609b99c3cc4e",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":false,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"bad\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/initialized\"}",
    "frame_sha256": "59951ca0b212b103876fa23a9e58bcbbc8fbcc0120e3f5ee7214461e2bd1cd5e",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":false},\"method\":\"notifications/initialized\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"jsonrpc\",\"2.0\"],[\"method\",\"notifications/initialized\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"method\":\"ping\"}",
    "frame_sha256": "85465608a33a5a6fce5da4c01d8204d8ac03895f5cf7be131dad34245a013657",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":false},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"method\":\"private_method\"}",
    "frame_sha256": "308f30e045b31933d636bade6aae0ece0c95561135ab4aab6e9704e0fd7477f0",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":false},\"method\":\"private_method\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"jsonrpc\",\"2.0\"],[\"method\",\"private_method\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\",\"method\":\"tools/call\"}",
    "frame_sha256": "6df4e2f26c0e1b2cff8658620bd34f6006067bf9604c1a7b9d21032dbdab5f8e",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":false},\"method\":\"tools/call\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"2.0\"}",
    "frame_sha256": "049aba59a5035ce3ebb781e1f9176faa52302d2f5cb23b9a692673654f334fe6",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":false},\"method\":null,\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"jsonrpc\",\"2.0\"]]}"
  },
  {
    "frame_utf8": "{\"jsonrpc\":\"bad\",\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"ping\"}",
    "frame_sha256": "8739b3476173002d35dbf46cb0c86c9b7c49a64363ac5378535c57489fb0f12c",
    "disposition": "parsed",
    "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"ping\",\"params\":null,\"paramsDefaulted\":true,\"progressToken\":null}",
    "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"ping\"]]}"
  }
];
// Independent exact-number scalar PORT witnesses; only five keyed representation/payload values.
const scalarInputs = [
  {
    "representation": "signed_integer",
    "payload": "9223372036854775807",
    "expected_UTF8": "9223372036854775807"
  },
  {
    "representation": "unsigned_integer",
    "payload": "9223372036854775808",
    "expected_UTF8": "9223372036854775808"
  },
  {
    "representation": "binary64",
    "payload": "8000000000000000",
    "expected_UTF8": "-0.0"
  },
  {
    "representation": "binary64",
    "payload": "3ff0000000000000",
    "expected_UTF8": "1.0"
  },
  {
    "representation": "binary64",
    "payload": "3ff8000000000000",
    "expected_UTF8": "1.5"
  }
] as const;
const metadataInputs = {
  "source_profile": "RemoteReadOnly",
  "instructions": "Use this remote read-only Health.md surface for readiness and typed queries only. Pairing and file-export tools are unavailable; the server operator must pair its iPhone source outside MCP. Keep Health.md foreground on the paired iPhone. Prefer healthmd_sleep_sessions for sleep, healthmd_workouts for workouts, and healthmd_metric_chart for metric series. Every query is live; there is no synchronized health-data corpus or fallback.",
  "serverInfo": {
    "name": "healthmd-mcp",
    "version": "0.1.0-alpha.7"
  },
  "protocol_versions": [
    "2024-11-05",
    "2025-03-26",
    "2025-06-18",
    "2025-11-25"
  ],
  "capabilities_without_UI": {
    "tools": {
      "listChanged": false
    }
  },
  "UI_extension": "io.modelcontextprotocol/ui",
  "UI_mime": "text/html;profile=mcp-app",
  "capabilities_with_UI": {
    "extensions": {
      "io.modelcontextprotocol/ui": {
        "mimeTypes": [
          "text/html;profile=mcp-app"
        ]
      }
    },
    "resources": {
      "listChanged": false,
      "subscribe": false
    },
    "tools": {
      "listChanged": false
    }
  },
  "source_bases": [
    "jsonrpc.rs PROTOCOLS/initialize/getprotocolVersion",
    "application.rs HealthMdSession.instructions RemoteReadOnly",
    "Cargo workspace0.1.0-alpha.7"
  ],
  "not_qualified": "No actual tools/resources/HTML/schema common adapter, native data or client"
} as const;
const defaultResultWire = "{\"kind\":\"object\",\"entries\":[[\"content\",[{\"kind\":\"object\",\"entries\":[[\"text\",\"{\\\"ready\\\":true}\"],[\"type\",\"text\"]]}]],[\"isError\",false]]}";
const companionLiterals = [
  {
    "case_id": "foreign-source-parse-error-outcome",
    "basis": "Own source-error token exactframe/factory membership, before properties; semantic validity never grants token ownership",
    "stimulus": {
      "frame": "{\"jsonrpc\":\"2.0\",\"id\":1e9999,\"method\":\"ping\"}",
      "codec_return": "source_parse_error_from_other_factory",
      "property_traps": "throw_and_count"
    },
    "expected": {
      "kind": "private_failure",
      "response_utf8": null,
      "response_LF": false,
      "dispatch_calls": 0,
      "metadata_calls": 0,
      "allocation_calls": 0,
      "release_ACKs": 0,
      "source_calls": 0,
      "forbidden_IO_calls": 0,
      "proxy_traps": 0,
      "private_failure": "private_rpc_codec",
      "publication_calls": 0
    }
  },
  {
    "case_id": "previous-frame-source-parse-error-outcome",
    "basis": "Same factory and identical primitive bytes do not admit a previous callback/frame token into current inspection",
    "stimulus": {
      "handle_before": "{\"jsonrpc\":\"2.0\",\"id\":1e9999,\"method\":\"ping\"}",
      "handle_before_response_utf8": "{\"error\":{\"code\":-32700,\"message\":\"Parse error\"},\"id\":null,\"jsonrpc\":\"2.0\"}",
      "frame": "{\"jsonrpc\":\"2.0\",\"id\":1e9999,\"method\":\"ping\"}",
      "codec_return": "saved_source_parse_error_from_previous_frame_same_factory"
    },
    "expected": {
      "kind": "private_failure",
      "response_utf8": null,
      "response_LF": false,
      "dispatch_calls": 0,
      "metadata_calls": 0,
      "allocation_calls": 0,
      "release_ACKs": 0,
      "source_calls": 0,
      "forbidden_IO_calls": 0,
      "proxy_traps": 0,
      "private_failure": "private_rpc_codec",
      "publication_calls": 0
    }
  },
  {
    "case_id": "scope-close-inside-source-parse-error-callback",
    "basis": "Sentinel for originalScope observed after trusted codec callback before source-error disposition/publication",
    "stimulus": {
      "frame": "{\"jsonrpc\":\"2.0\",\"id\":1e9999,\"method\":\"ping\"}",
      "codec_action": "issue_current_source_parse_error_then_actual_Scope_close_original_and_return_token_normally"
    },
    "expected": {
      "kind": "private_failure",
      "response_utf8": null,
      "response_LF": false,
      "dispatch_calls": 0,
      "metadata_calls": 0,
      "allocation_calls": 0,
      "release_ACKs": 0,
      "source_calls": 0,
      "forbidden_IO_calls": 0,
      "proxy_traps": 0,
      "private_failure": "owned_handoff_closed",
      "publication_calls": 0,
      "callbacks_after_close": 0
    }
  }
] as const;

interface Stimulus { readonly frame: string; readonly actions?: readonly Readonly<Record<string, unknown>>[]; readonly [key: string]: unknown }
interface Literal { readonly case_id: string; readonly stimulus: Stimulus; readonly expected: Readonly<Record<string, unknown>> }
const literals: readonly Literal[] = rpcEnvelopeFixture.cases;
const allLiterals: readonly Literal[] = [...literals, ...companionLiterals];
const sources = new Map(frameInputs.map((row) => [row.frame_utf8, row]));
const secret = "PRIVATE_DO_NOT_ECHO";
const fault = (code: FixedFailure["code"]): FixedFailure => ({ code });
const q = (value: string): string => JSON.stringify(value); // Selected scalar strings, never Number serde equivalence.
function sourceOrder(a: string, b: string): number {
  const left = Array.from(a, (c) => c.codePointAt(0)!), right = Array.from(b, (c) => c.codePointAt(0)!);
  for (let i = 0; i < Math.min(left.length, right.length); i++) if (left[i] !== right[i]) return left[i]! - right[i]!;
  return left.length - right.length;
}
/** Trusted pure five-witness port; no general binary64 parser/renderer or envelope lookup. */
function scalar(value: SourceNumber): string {
  if (value.kind === "binary64") {
    const witness = scalarInputs.find((row) => row.representation === "binary64" && row.payload === value.bits);
    assert.ok(witness, "unadmitted synthetic float witness"); return witness.expected_UTF8;
  }
  assert.match(value.decimal, /^(0|-?[1-9][0-9]*)$/);
  const n = BigInt(value.decimal);
  assert.ok(value.kind === "signed_integer" ? n >= -(1n << 63n) && n <= (1n << 63n) - 1n : n >= 0n && n <= (1n << 64n) - 1n);
  return value.decimal;
}
function render(value: SourceValue): string {
  if (value === null) return "null";
  if (typeof value === "string") return q(value);
  if (typeof value === "boolean") return value ? "true" : "false";
  if (Array.isArray(value)) return "[" + value.map(render).join(",") + "]";
  const tagged = value as SourceNumber | { readonly kind: "object"; readonly entries: readonly (readonly [string, SourceValue])[] };
  if (tagged.kind !== "object") return scalar(tagged);
  return "{" + [...tagged.entries].sort(([a], [b]) => sourceOrder(a, b)).map(([key, child]) => q(key) + ":" + render(child)).join(",") + "}";
}
/** Test-owned ordinary constants only (metadata/progress); raw caller JSON is never parsed here. */
function constant(value: unknown): SourceValue {
  if (value === null || typeof value === "string" || typeof value === "boolean") return value;
  if (typeof value === "number") {
    assert.ok(Number.isSafeInteger(value)); return { kind: value < 0 ? "signed_integer" : "unsigned_integer", decimal: BigInt(value).toString() };
  }
  if (Array.isArray(value)) return value.map(constant);
  assert.ok(value && typeof value === "object");
  return { kind: "object", entries: Object.entries(value).sort(([a], [b]) => sourceOrder(a, b)).map(([key, child]) => [key, constant(child)] as const) };
}
const wire = (value: SourceValue): string => JSON.stringify(value); // Private tagged JSON contains numbers as strings.
function field(value: SourceValue | undefined, key: string): SourceValue | undefined {
  return value !== null && value !== undefined && typeof value === "object" && !Array.isArray(value) && "kind" in value && value.kind === "object" ? value.entries.find(([name]) => name === key)?.[1] : undefined;
}
function sourceInput(frame: string): FrameInput {
  const fixed = sources.get(frame); if (fixed) return fixed;
  const seed = /^\{"jsonrpc":"2\.0","id":([1-9][0-9]*),"method":"ping"\}$/.exec(frame);
  assert.ok(seed, "frame absent from independently frozen source inputs");
  const decimal = seed[1]!; assert.ok(BigInt(decimal) >= 1n && BigInt(decimal) <= 16385n);
  return { frame_utf8: frame, frame_sha256: "parametric-independent-input", disposition: "parsed", source_value_wire: null,
    primitive_metadata_wire: JSON.stringify({ rootObject: true, version2: true, id: { present: true, scalar: "unsigned_integer", canonicalEncoded: decimal, validI64OrString: true }, method: "ping", params: null, paramsDefaulted: true, progressToken: null }) };
}
function rawSourceValue(frame: string): SourceValue {
  const input = sourceInput(frame); assert.ok(input.source_value_wire); return JSON.parse(input.source_value_wire) as SourceValue;
}
function failureCode(exit: Exit.Exit<unknown, unknown>): string | null {
  if (Exit.isSuccess(exit)) return null;
  if (exit.cause.reasons.some((reason) => reason._tag === "Interrupt")) return "interrupted";
  for (const reason of exit.cause.reasons) if (reason._tag === "Fail" || reason._tag === "Die") {
    const value = reason._tag === "Fail" ? reason.error : reason.defect;
    if (value && typeof value === "object" && "code" in value) return String(value.code);
  }
  return "unexpected_failure";
}
interface Counters { dispatch_calls: number; metadata_calls: number; allocation_calls: number; acquire_attempts: number; release_ACKs: number; release_attempts: number; source_calls: number; forbidden_IO_calls: number; proxy_traps: number; callbacks_after_close: number; materializations: number; publication_calls: number; inspection_calls: number; serializer_calls: number; authority_calls: number; sink_calls: number }
const counters = (): Counters => ({ dispatch_calls: 0, metadata_calls: 0, allocation_calls: 0, acquire_attempts: 0, release_ACKs: 0, release_attempts: 0, source_calls: 0, forbidden_IO_calls: 0, proxy_traps: 0, callbacks_after_close: 0, materializations: 0, publication_calls: 0, inspection_calls: 0, serializer_calls: 0, authority_calls: 0, sink_calls: 0 });
const subtraction = (current: Counters, before: Counters): Counters => Object.fromEntries(Object.keys(current).map((key) => [key, current[key as keyof Counters] - before[key as keyof Counters]])) as unknown as Counters;
interface Observation extends Counters { readonly result: string; readonly response: string | null; readonly progress: readonly string[]; readonly beforeACK: boolean; readonly maxPending: number; readonly secondResult: string | null; readonly leaked: boolean; readonly escapedViewsDead: boolean }
function exercise(scene: Stimulus): Effect.Effect<Observation, unknown> {
  return Effect.scoped(Effect.gen(function* () {
    const original = yield* Scope.make();
    yield* Effect.addFinalizer(() => Scope.close(original, Exit.succeed(undefined)));
    let closed = false;
    const close = () => { Effect.runSync(Scope.close(original, Exit.succeed(undefined))); closed = true; };
    const actions = scene.actions ?? [];
    const get = (key: string): unknown => scene[key] ?? actions.find((entry) => key in entry)?.[key];
    const closure = get("close_original_scope");
    const closeName = typeof closure === "string" ? closure.replaceAll("-", "_") : "";
    const counts = counters(), progress: string[] = [];
    const entered = yield* Deferred.make<void>(), proceed = yield* Deferred.make<void>(), releasing = yield* Deferred.make<void>(), ack = yield* Deferred.make<void>();
    let beforeACK = false, pending = 0, maxPending = 0, secondResult: string | null = null;
    const callback = () => { if (closed) counts.callbacks_after_close++; };
    let envelope: RpcEnvelope, session: OwnedSession, foreignSession: OwnedSession | undefined, foreignOutput: OwnedOutput | undefined, foreignInspection: unknown;
    let capture: unknown, savedError: unknown, savedIssuer: CodecIssuer | undefined, savedFrame: OwnedFrame | undefined;
    let requestFrame = scene.frame, target = false, ownOutput: OwnedOutput | null = null;
    let lastRequestView: { spanText(request: unknown, span: unknown): Effect.Effect<string | null, FixedFailure> } | undefined, lastRequest: OwnedParsed | undefined, lastMetadata: InspectionMetadata | undefined;
    let escapedValues: (() => unknown) | undefined;
    const unknownProxy = () => new Proxy({}, Object.fromEntries(["get", "set", "has", "ownKeys", "getOwnPropertyDescriptor", "defineProperty", "getPrototypeOf", "setPrototypeOf", "isExtensible", "preventExtensions", "deleteProperty"].map((name) => [name, () => { counts.proxy_traps++; throw new Error(secret); }])));
    const cancellation = get("interrupt_owned_fiber_at");
    const late = get("pause_acquire_before_return") === true;
    const sinkPending = cancellation === "progress-backpressure" || get("progress_sink") === "pending_forever_until_interrupt";
    const busy = get("start_first_handle") !== undefined;
    const atAuthority = (phase: string): boolean => closeName === "authority_" + phase || closeName === "source_current_" + phase || closeName === "grant_current_" + phase || closeName === "assert_current_callback" && phase === "assert_current";
    const ports: TrustedFactoryInputs = {
      codec: {
        inspect(frame, issuer, view) {
          callback(); counts.inspection_calls++; const text = view.frameText(frame); assert.equal(typeof text, "string"); requestFrame = text!;
          const source = sourceInput(text!); let result = source.disposition === "source_parse_error" ? issuer.sourceParseError(frame) : issuer.inspection(source.primitive_metadata_wire, frame);
          assert.ok(result); capture = result;
          if (!target) { savedError = source.disposition === "source_parse_error" ? result : savedError; return result; }
          if (closeName === "parser_callback") close();
          if (get("codec_action") === "issue_current_source_parse_error_then_actual_Scope_close_original_and_return_token_normally") close();
          if (get("codec_callback_reenters_same_session_handle") === true) {
            const nestedFrame = actions.find((entry) => entry.codec_callback_reenters_same_session_handle === true)?.frame;
            const nested = Effect.runSync(Effect.exit(envelope.handle(session, nestedFrame)));
            assert.equal(failureCode(nested), "private_rpc_busy");
            if (Exit.isFailure(nested)) { const failed = nested.cause.reasons.find((r) => r._tag === "Fail"); if (failed && failed._tag === "Fail") throw failed.error; }
            throw new Error("nested call unexpectedly succeeded");
          }
          if (get("invoke_saved_issuer_after_callback_returns") === true) return savedIssuer!.inspection(get("primitive_wire"), savedFrame!);
          if (get("save_inspection_issuer") === true) { savedIssuer = issuer; savedFrame = frame; }
          const offset = get("inspection_wire_offset_raw_token");
          if (typeof offset === "string") {
            assert.ok(source.primitive_metadata_wire); const mutated = source.primitive_metadata_wire.replace(/"params":\{"start":[0-9]+/, '"params":{"start":' + offset);
            assert.notEqual(mutated, source.primitive_metadata_wire); return issuer.inspection(mutated, frame);
          }
          const returned = get("codec_return");
          if (returned === "foreign_Proxy_all_traps_throw_count") return unknownProxy();
          if (returned === "owned_inspection_from_other_factory" || returned === "source_parse_error_from_other_factory") return foreignInspection;
          if (returned === "saved_source_parse_error_from_previous_frame_same_factory") return savedError;
          return result;
        },
        serialize(request, reply, issuer, view) {
          callback(); counts.serializer_calls++; const body = view.inspectReply(reply); assert.ok(body);
          let text: string;
          if (body.kind === "error") text = '{"error":{"code":' + BigInt(body.code).toString() + ',"message":' + q(body.fixedMessage) + '},"id":' + body.idCanonicalEncoded + ',"jsonrpc":"2.0"}';
          else if (body.kind === "success") text = '{"id":' + body.idCanonicalEncoded + ',"jsonrpc":"2.0","result":' + render(view.readJson(body.result)) + '}';
          else text = render(view.readJson(body.notification));
          escapedValues = () => view.inspectReply(reply);
          const result = issuer.encoded(text, request); assert.ok(result);
          if (target && closeName === "serializer_callback") close();
          return target && get("serializer_return") === "foreign_Proxy_all_traps_throw_count" ? unknownProxy() : result;
        },
      },
      authority: { check(request, phase, view) { return Effect.gen(function* () {
        callback(); counts.authority_calls++; assert.ok(view.inspect(request));
        if (!target) return;
        if (atAuthority(phase)) close();
        if (get("authority_action") && get("phase") === phase) return yield* Effect.fail(fault("private_rpc_authority"));
        if (cancellation === "after-allocation" && phase === "before_allocation" && counts.allocation_calls > 0) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
      }); } },
      dispatcher: {
        acquire() { return Effect.gen(function* () {
          callback(); counts.acquire_attempts++;
          if (target && cancellation === "pending-acquire") { yield* Deferred.succeed(entered, undefined); yield* Effect.interruptible(Deferred.await(proceed)); }
          counts.allocation_calls++; const handle = Object.freeze({ privateFakeResource: true });
          if (target && late) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
          if (target && closeName === "allocator_return") close();
          return handle;
        }); },
        release(handle) { return Effect.gen(function* () {
          // Release is expressly permitted after lifetime closure; no new trusted acquisition.
          assert.ok(handle && typeof handle === "object"); counts.release_attempts++;
          if (target && get("pause_release_ACK") === true) { yield* Deferred.succeed(releasing, undefined); yield* Deferred.await(ack); }
          if (target && get("release_action") === "fail_fixed_cleanup") return yield* Effect.fail(fault("private_rpc_cleanup"));
          counts.release_ACKs++;
        }); },
        dispatch(request, _lease, emit, view, issuer) { return Effect.gen(function* () {
          callback(); counts.dispatch_calls++;
          lastRequestView = view; lastRequest = request; lastMetadata = view.inspect(request) ?? undefined;
          assert.ok(lastMetadata); if (lastMetadata.params) { assert.notEqual(yield* view.spanText(request, lastMetadata.params), null); counts.materializations++; }
          if (target && closeName === "dispatcher_callback") close();
          if (target && get("dispatch_action") === "die_with_private_sentinel") return yield* Effect.die(new Error(secret));
          if (busy && !target || target && (cancellation === "dispatch-pending" || cancellation === "EOF")) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
          const sourceParams = field(rawSourceValue(requestFrame), "params"), token = field(field(sourceParams, "_meta"), "progressToken");
          const fixedProgress = get("progress") ?? get("dispatcher_emits_fixed_progress") ?? get("fixed_progress") ?? (sinkPending || closeName === "progress_sink_callback" ? { progress: 10, total: 120, message: "Waiting for the paired source." } : undefined);
          if (fixedProgress !== undefined) {
            const update = constant(fixedProgress);
            const params: SourceValue = { kind: "object", entries: [...(update && typeof update === "object" && !Array.isArray(update) && "kind" in update && update.kind === "object" ? update.entries : []), ["progressToken", token ?? null]] };
            const notification = issuer.json(wire({ kind: "object", entries: [["jsonrpc", "2.0"], ["method", "notifications/progress"], ["params", params]] })); assert.ok(notification);
            const emitCount = get("dispatch_emit_count");
            if (typeof emitCount === "number") yield* Effect.forEach(Array.from({ length: emitCount }), () => emit(notification), { concurrency: "unbounded", discard: true });
            else yield* emit(notification);
          }
          const operationError = get("dispatcher_fixed_error") as { code: number; message: string } | undefined;
          if (operationError) { const result = issuer.error(operationError.code, operationError.message); assert.ok(result); return result; }
          if (get("operation_issuer") === "error") { const result = issuer.error(get("code"), get("fixed_message")); assert.ok(result); return result; }
          const ownedWire = get("common_owned_result_wire");
          const result = issuer.json(typeof ownedWire === "string" ? ownedWire : defaultResultWire); assert.ok(result); return result;
        }); },
      },
      metadata: { describe(request, view, issuer) { return Effect.gen(function* () {
        callback(); counts.metadata_calls++; const md = view.inspect(request); assert.ok(md);
        if (md.params) { assert.notEqual(yield* view.spanText(request, md.params), null); counts.materializations++; }
        assert.equal(md.method, "initialize", "real catalogs/resources remain separately owned");
        const params = field(rawSourceValue(requestFrame), "params"), version = field(params, "protocolVersion");
        if (typeof version !== "string" || !(metadataInputs.protocol_versions as readonly string[]).includes(version)) { const result = issuer.error(-32602, "Unsupported MCP protocol version"); assert.ok(result); return result; }
        const types = field(field(field(field(params, "capabilities"), "extensions"), metadataInputs.UI_extension), "mimeTypes");
        const ui = Array.isArray(types) && types.some((value) => value === metadataInputs.UI_mime);
        const result = issuer.json(wire(constant({ capabilities: ui ? metadataInputs.capabilities_with_UI : metadataInputs.capabilities_without_UI, instructions: metadataInputs.instructions, protocolVersion: version, serverInfo: metadataInputs.serverInfo }))); assert.ok(result); return result;
      }); } },
      progress: { publish(output, view) { return Effect.gen(function* () {
        callback(); counts.sink_calls++; pending++; maxPending = Math.max(maxPending, pending);
        yield* Effect.addFinalizer(() => Effect.sync(() => { pending--; }));
        const text = yield* view.encodedText(output); assert.equal(typeof text, "string");
        if (target && closeName === "progress_sink_callback") { close(); return; }
        if (target && sinkPending) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
        progress.push(text!);
      }).pipe(Effect.scoped); } },
    };
    envelope = yield* createRpcEnvelope(ports).pipe(Effect.provideService(Scope.Scope, original));
    session = yield* envelope.open().pipe(Effect.provideService(Scope.Scope, original));
    const open = () => envelope.open().pipe(Effect.provideService(Scope.Scope, original));
    const foreign = get("codec_return") === "owned_inspection_from_other_factory" || get("codec_return") === "source_parse_error_from_other_factory" || get("session_override") || get("encode_output_override") === "other_factory_owned_output";
    if (foreign) {
      const other = yield* createRpcEnvelope(ports).pipe(Effect.provideService(Scope.Scope, original));
      foreignSession = yield* other.open().pipe(Effect.provideService(Scope.Scope, original));
      const output = yield* other.handle(foreignSession, scene.frame); assert.ok(output); foreignOutput = output; foreignInspection = capture;
    }
    if (get("save_inspection_issuer") === true) {
      // Callback-only issuer captured in a real prior callback, never revived after return.
      const source = sourceInput(scene.frame); assert.ok(source.primitive_metadata_wire);
      const capturing = { ...ports, codec: { ...ports.codec, inspect(frame: OwnedFrame, issuer: CodecIssuer) { savedIssuer = issuer; savedFrame = frame; return issuer.inspection(source.primitive_metadata_wire, frame); } } };
      const prior = yield* createRpcEnvelope(capturing).pipe(Effect.provideService(Scope.Scope, original)); const priorSession = yield* prior.open().pipe(Effect.provideService(Scope.Scope, original));
      yield* prior.handle(priorSession, scene.frame); assert.equal(savedIssuer!.inspection("{}", savedFrame!), null);
    }
    const beforeFrame = get("handle_before");
    if (typeof beforeFrame === "string") {
      const before = yield* envelope.handle(session, beforeFrame); assert.ok(before);
      const text = yield* envelope.encode(session, before); const expectedBefore = get("expected_response") ?? get("response_utf8") ?? get("handle_before_response_utf8");
      if (typeof expectedBefore === "string") assert.equal(text, expectedBefore);
    }
    const seed = get("seed_by_real_successful_handle_calls") as { first_integer_id: number; last_integer_id: number; session?: string } | undefined;
    if (seed) {
      const destination = seed.session === "other" ? yield* open() : session;
      for (let id = seed.first_integer_id; id <= seed.last_integer_id; id++) {
        const output = yield* envelope.handle(destination, '{"jsonrpc":"2.0","id":' + BigInt(id).toString() + ',"method":"ping"}'); assert.ok(output);
        assert.equal(yield* envelope.encode(destination, output), '{"id":' + BigInt(id).toString() + ',"jsonrpc":"2.0","result":{}}');
      }
    }
    if (closure === true || closeName === "before_handle") close();
    let frame: unknown = scene.frame;
    const override = get("frame_override") as Readonly<Record<string, unknown>> | undefined;
    if (override) {
      if (override.kind === "Proxy") frame = unknownProxy();
      else if (override.kind === "object") frame = { toString() { counts.proxy_traps++; throw new Error(secret); }, valueOf() { counts.proxy_traps++; throw new Error(secret); }, [Symbol.toPrimitive]() { counts.proxy_traps++; throw new Error(secret); } };
      else if (override.kind === "primitive_UTF16_code_units") frame = String.fromCharCode(...override.units as number[]);
      else if (override.kind === "repeat_ASCII") frame = String(override.character).repeat(Number(override.count));
      else if (override.kind === "nested_array_literal") frame = "[".repeat(Number(override.array_levels)) + String(override.leaf) + "]".repeat(Number(override.array_levels));
      else if (override.kind === "flat_array_literal") frame = "[" + Array.from({ length: Number(override.element_count) }, () => String(override.element)).join(",") + "]";
    }
    let background: Fiber.Fiber<OwnedOutput | null, FixedFailure> | undefined;
    if (busy) {
      background = yield* Effect.forkChild(envelope.handle(session, get("start_first_handle"))); yield* Deferred.await(entered);
    }
    const baseline = { ...counts }; progress.length = 0; target = true;
    let operation = envelope.handle(get("session_override") ? foreignSession : session, frame);
    if (get("handle_original_session_under") === "new_scope_with_reprovided_services") {
      const replacementScope = yield* Scope.make();
      yield* Effect.addFinalizer(() => Scope.close(replacementScope, Exit.succeed(undefined)));
      // Real new Scope and new factory injection cannot revive original session membership/lifetime.
      yield* createRpcEnvelope({ ...ports }).pipe(Effect.provideService(Scope.Scope, replacementScope));
      operation = operation.pipe(Effect.provideService(Scope.Scope, replacementScope));
    }
    let exit: Exit.Exit<OwnedOutput | null, FixedFailure>;
    if (cancellation === "before-callback") {
      // Interruption before candidate evaluation, not an OS/peer transport cancellation claim.
      const child = yield* Effect.forkChild(Deferred.await(proceed).pipe(Effect.andThen(operation))); yield* Fiber.interrupt(child); exit = yield* Fiber.await(child);
    } else if (cancellation || late || get("interrupt_owned_handle") === true) {
      const child = yield* Effect.forkChild(operation); yield* Deferred.await(entered);
      const stopping = yield* Effect.forkChild(Fiber.interrupt(child)); yield* Effect.yieldNow;
      if (late) yield* Deferred.succeed(proceed, undefined);
      yield* Fiber.join(stopping); exit = yield* Fiber.await(child);
    } else if (get("pause_release_ACK") === true) {
      const child = yield* Effect.forkChild(operation); yield* Deferred.await(releasing);
      beforeACK = child.pollUnsafe() !== undefined; assert.equal(beforeACK, false);
      yield* Deferred.succeed(ack, undefined); exit = yield* Fiber.await(child);
    } else exit = yield* Effect.exit(operation);
    let response: string | null = null;
    if (Exit.isSuccess(exit)) {
      ownOutput = exit.value;
      if (ownOutput) {
        if (get("encode_output_override")) {
          const unknown = get("encode_output_override") === "foreign_Proxy_all_traps_throw_count" ? unknownProxy() : foreignOutput;
          const encoded = yield* Effect.exit(envelope.encode(session, unknown));
          exit = Exit.isFailure(encoded) ? Exit.failCause(encoded.cause) : Exit.succeed(ownOutput);
        } else if (get("handle_to_owned_output_without_encode") === true) {
          const checked = yield* Effect.exit(envelope.assertCurrent(session, ownOutput)); exit = Exit.isFailure(checked) ? Exit.failCause(checked.cause) : Exit.succeed(ownOutput);
        } else { const encoded = yield* Effect.exit(envelope.encode(session, ownOutput)); if (Exit.isFailure(encoded)) exit = Exit.failCause(encoded.cause); else { response = encoded.value; counts.publication_calls++; } }
      }
    }
    if (get("release_action") === "fail_fixed_cleanup") {
      const second = yield* Effect.exit(envelope.handle(session, '{"jsonrpc":"2.0","id":2,"method":"ping"}')); secondResult = failureCode(second); assert.equal(secondResult, "private_rpc_cleanup");
    }
    const observed = subtraction(counts, baseline);
    if (background) { yield* Fiber.interrupt(background); assert.equal(counts.release_ACKs - baseline.release_ACKs, 1); }
    const escapedText = lastRequestView && lastRequest && lastMetadata?.params ? yield* lastRequestView.spanText(lastRequest, lastMetadata.params) : null;
    const escapedViewsDead = escapedText === null && (!escapedValues || escapedValues() === null);
    return { ...observed, result: failureCode(exit) ?? (Exit.isSuccess(exit) && exit.value === null ? "notification" : "response"), response, progress: [...progress], beforeACK, maxPending, secondResult, escapedViewsDead,
      leaked: JSON.stringify(exit).includes(secret) || (response?.includes(secret) ?? false) };
  }));
}
for (const literal of allLiterals) test(`private MCP envelope ${literal.case_id}`, { timeout: 20000 }, async () => {
  const observed = await Effect.runPromise(exercise(literal.stimulus));
  const expected = literal.expected;
  assert.equal(observed.result, expected.private_failure ?? expected.kind);
  assert.equal(observed.response, expected.response_utf8);
  assert.equal(observed.response?.endsWith("\n") ?? false, expected.response_LF);
  for (const key of ["dispatch_calls", "metadata_calls", "allocation_calls", "release_ACKs", "source_calls", "forbidden_IO_calls", "proxy_traps"] as const) assert.equal(observed[key], expected[key], key);
  for (const key of ["release_attempts", "callbacks_after_close", "publication_calls"] as const) if (key in expected) assert.equal(observed[key], expected[key], key);
  if ("progress_utf8" in expected) assert.deepEqual(observed.progress, expected.progress_utf8);
  if ("progress_count" in expected) assert.equal(observed.progress.length, expected.progress_count);
  if ("publication_before_ACK" in expected) assert.equal(observed.beforeACK, false);
  if ("progress_pending_at_interrupt" in expected) assert.ok(observed.maxPending > 0);
  if (expected.private_failure === "private_rpc_input") { assert.equal(observed.inspection_calls, 0); assert.equal(observed.serializer_calls, 0); assert.equal(observed.authority_calls, 0); }
  if (expected.private_failure === "private_rpc_authority") assert.equal(observed.materializations, 0);
  if (literal.stimulus.trusted_parser_outcome === "own_source_parse_error") assert.equal(observed.authority_calls, 0);
  assert.ok(observed.maxPending <= 16); assert.equal(observed.leaked, false); assert.equal(observed.escapedViewsDead, true);
});
for (const input of scalarInputs) test(`synthetic exact scalar port ${input.representation}/${input.payload}`, () => {
  assert.equal(scalar(input.representation === "binary64" ? { kind: "binary64", bits: input.payload } : { kind: input.representation, decimal: input.payload }), input.expected_UTF8);
});

test("owned session/output membership rejects unknown and revoked Proxies before host callbacks", async () => {
  await Effect.runPromise(Effect.scoped(Effect.gen(function* () {
    let traps = 0, callbacks = 0;
    const unexpected = (): never => { callbacks++; throw new Error(secret); };
    const inputs: TrustedFactoryInputs = {
      codec: { inspect: unexpected, serialize: unexpected },
      authority: { check: () => Effect.sync(unexpected) },
      dispatcher: { acquire: () => Effect.sync(unexpected), release: () => Effect.sync(unexpected), dispatch: () => Effect.sync(unexpected) },
      metadata: { describe: () => Effect.sync(unexpected) }, progress: { publish: () => Effect.sync(unexpected) },
    };
    const envelope = yield* createRpcEnvelope(inputs), session = yield* envelope.open();
    const throwing = new Proxy({}, { get() { traps++; throw new Error(secret); }, ownKeys() { traps++; throw new Error(secret); }, getPrototypeOf() { traps++; throw new Error(secret); } });
    const revoked = Proxy.revocable({}, {}); revoked.revoke();
    for (const unknown of [throwing, revoked.proxy, null, false, 0, "session", Object.create(null), () => undefined]) {
      assert.equal(failureCode(yield* Effect.exit(envelope.handle(unknown, '{"jsonrpc":"2.0","id":1,"method":"ping"}'))), "private_rpc_owned");
      assert.equal(failureCode(yield* Effect.exit(envelope.encode(session, unknown))), "private_rpc_owned");
      assert.equal(failureCode(yield* Effect.exit(envelope.assertCurrent(session, unknown))), "private_rpc_owned");
    }
    assert.equal(traps, 0); assert.equal(callbacks, 0);
  })));
});
test("synthetic float port rejects payloads outside its three independent witnesses", () => {
  assert.throws(() => scalar({ kind: "binary64", bits: "0000000000000000" }), /unadmitted synthetic float witness/);
});
test("fixture inputs remain source-only and complete without an expected-response lookup in ports", () => {
  assert.equal(literals.length, 143); assert.equal(frameInputs.length, 85); assert.equal(companionLiterals.length, 3);
  assert.equal(new Set(frameInputs.map((input) => input.frame_utf8)).size, 85);
  for (const literal of allLiterals) assert.ok(sources.has(literal.stimulus.frame));
  assert.equal(metadataInputs.UI_mime, "text/html;profile=mcp-app");
});

// Eight independently frozen pre-repair literals: exact root-reviewed data, assertions only.
const perReadLiterals = [
  {
    "case_id": "fresh-own-span-read-once",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
    "callback": "dispatcher",
    "actions": [
      {
        "snapshot_counters": "callback_entry"
      },
      {
        "read": "same_factory_request_original_params_span",
        "execute_times": 1,
        "authority_response": "permit"
      },
      {
        "snapshot_counters": "before_callback_return"
      }
    ],
    "expected": {
      "outer_authority_checks_at_callback_entry": 3,
      "read_authority_checks_delta": 1,
      "read_authority_phases": [
        "before_materialization"
      ],
      "successful_payload_materializations_delta": 1,
      "returned_span_texts": [
        "{\"name\":\"healthmd_status\"}"
      ],
      "proxy_traps_delta": 0,
      "acquired": 1,
      "release_ACKs_after_handle_settles": 1,
      "fixed_failure": null,
      "escaped_callbacks": 0
    }
  },
  {
    "case_id": "revoke-between-two-executions-of-same-own-read-effect",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
    "callback": "dispatcher",
    "actions": [
      {
        "construct_read_effect_once": "own_request_params_span"
      },
      {
        "snapshot_counters": "callback_entry"
      },
      {
        "execute_read_effect": 1,
        "authority_response": "permit"
      },
      {
        "trusted_original_authority_state": "revoked_latest_frontier",
        "Scope_remains_live": true
      },
      {
        "execute_same_read_effect": 2,
        "authority_response": "deny_fixed_private_rpc_authority"
      }
    ],
    "expected": {
      "outer_authority_checks_at_callback_entry": 3,
      "read_authority_checks_delta": 2,
      "read_authority_phases": [
        "before_materialization",
        "before_materialization"
      ],
      "successful_payload_materializations_delta": 1,
      "returned_span_texts": [
        "{\"name\":\"healthmd_status\"}"
      ],
      "second_payload_returned": false,
      "proxy_traps_delta": 0,
      "acquired": 1,
      "release_ACKs_after_handle_settles": 1,
      "fixed_failure": "private_rpc_authority",
      "output_or_delivery_after_revoke": 0
    }
  },
  {
    "case_id": "metadata-revoke-before-first-own-read",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"extensions\":{\"io.modelcontextprotocol/ui\":{\"mimeTypes\":[\"text/html;profile=mcp-app\"]}}}}}",
    "callback": "metadata",
    "actions": [
      {
        "snapshot_counters": "callback_entry"
      },
      {
        "trusted_original_authority_state": "revoked_latest_frontier",
        "Scope_remains_live": true
      },
      {
        "construct_and_execute_read": "own_request_params_span",
        "authority_response": "deny_fixed_private_rpc_authority"
      }
    ],
    "expected": {
      "outer_authority_checks_at_callback_entry": 1,
      "read_authority_checks_delta": 1,
      "read_authority_phases": [
        "before_materialization"
      ],
      "successful_payload_materializations_delta": 0,
      "returned_span_texts": [],
      "proxy_traps_delta": 0,
      "acquired": 0,
      "release_ACKs_after_handle_settles": 0,
      "fixed_failure": "private_rpc_authority",
      "output_or_delivery_after_revoke": 0
    }
  },
  {
    "case_id": "original-Scope-closes-during-own-read-current-check",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
    "callback": "dispatcher",
    "actions": [
      {
        "snapshot_counters": "callback_entry"
      },
      {
        "execute_own_read_until": "captured_current_authority_Deferred_wait",
        "authority_entered_ACK": true
      },
      {
        "close_actual_original_factory_or_session_Scope_from_controller": true,
        "not_just_fake_flag": true
      },
      {
        "resume_inflight_current_check_normally": "permit"
      },
      {
        "wait_operation_cleanup_ACK": true
      }
    ],
    "expected": {
      "outer_authority_checks_at_callback_entry": 3,
      "read_authority_checks_delta": 1,
      "read_authority_phases": [
        "before_materialization"
      ],
      "successful_payload_materializations_delta": 0,
      "returned_span_texts": [],
      "proxy_traps_delta": 0,
      "acquired": 1,
      "release_ACKs_after_handle_settles": 1,
      "fixed_failure": "owned_handoff_closed",
      "new_trusted_callbacks_entered_after_close": 0,
      "output_or_delivery_after_close": 0
    }
  },
  {
    "case_id": "foreign-or-cross-context-span-membership-before-properties-and-check",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
    "callback": "dispatcher",
    "actions": [
      {
        "snapshot_counters": "callback_entry"
      },
      {
        "variants": "each_execute_same_lazy_view_read_without_catching_inside_port",
        "requests_and_spans": [
          {
            "request": "own_request",
            "span": "foreign_Proxy_all_traps_throw_increment"
          },
          {
            "request": "own_request",
            "span": "foreign_revoked_Proxy"
          },
          {
            "request": "own_request",
            "span": "authentic_span_from_different_request_or_factory_same_frame_bytes"
          },
          {
            "request": "foreign_Proxy_all_traps_throw_increment",
            "span": "own_span"
          }
        ]
      }
    ],
    "expected": {
      "outer_authority_checks_at_callback_entry": 3,
      "per_variant_read_authority_checks_delta": [
        0,
        0,
        0,
        0
      ],
      "per_variant_results": [
        null,
        null,
        null,
        null
      ],
      "successful_payload_materializations_delta": 0,
      "returned_span_texts": [],
      "proxy_traps_delta": 0,
      "acquired": 1,
      "release_ACKs_after_handle_settles": 1,
      "fixed_failure": null,
      "no_foreign_properties_observed": true
    }
  },
  {
    "case_id": "deferred-own-read-effect-executed-after-callback-cannot-reprovide-lifetime",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\"}}",
    "callback": "dispatcher",
    "actions": [
      {
        "snapshot_counters": "callback_entry"
      },
      {
        "construct_without_execute": "own_request_params_span_Effect"
      },
      {
        "callback_returns": "existing_common_owned_default_result"
      },
      {
        "wait_callback_and_handle_finish": true,
        "do_not_close_original_scope_yet": true
      },
      {
        "execute_retained_effect_in_fresh_Scope_and_reprovided_authority": "replacement_callback_would_increment_counter_and_permit"
      },
      {
        "repeat_after_original_Scope_closed": true
      }
    ],
    "expected": {
      "outer_authority_checks_at_callback_entry": 3,
      "read_authority_checks_delta_inside_callback": 0,
      "post_callback_read_authority_checks_delta": 0,
      "replacement_authority_calls": 0,
      "successful_payload_materializations_delta": 0,
      "late_results": [
        null,
        null
      ],
      "returned_span_texts": [],
      "proxy_traps_delta": 0,
      "acquired": 1,
      "release_ACKs_after_handle_settles": 1,
      "late_fixed_failure": null,
      "revival": false
    }
  },
  {
    "case_id": "escaped-metadata-view-and-issuer-dead-at-postcallback-authority",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"initialize\",\"params\":{\"protocolVersion\":\"2025-11-25\",\"capabilities\":{\"extensions\":{\"io.modelcontextprotocol/ui\":{\"mimeTypes\":[\"text/html;profile=mcp-app\"]}}}}}",
    "callback": "metadata",
    "actions": [
      {
        "inside_metadata_callback": "capture_authorized_view_request_params_span_and_OperationIssuer; construct_lazy_span_read_without_execute; issue_valid_existing_common_metadata_result"
      },
      {
        "metadata_callback_returns": true
      },
      {
        "reenter_from_original_authority": "next before_publication check after metadata return but while whole describe remains active"
      },
      {
        "execute_saved_read_effect": true
      },
      {
        "call_saved_operation_json": "existing_bounded_success_SourceValue_wire"
      },
      {
        "call_saved_operation_error": {
          "code": -32602,
          "fixedMessage": "Unsupported MCP protocol version"
        }
      },
      {
        "call_saved_view_with_foreign_revoked_Proxy": true
      },
      {
        "finish_original_authority": "permit"
      }
    ],
    "expected": {
      "outer_authority_checks_at_metadata_entry": 1,
      "reentry_authority_callback_is_outer_check": 1,
      "escaped_read_authority_checks_delta": 0,
      "escaped_read_result": null,
      "escaped_issuer_json_result": null,
      "escaped_issuer_error_result": null,
      "successful_payload_materializations_delta": 0,
      "proxy_traps_delta": 0,
      "acquired": 0,
      "release_ACKs": 0,
      "fixed_failure_for_escaped_read": null,
      "original_metadata_result_can_continue_with_fresh_outer_authority": true
    }
  },
  {
    "case_id": "escaped-dispatch-view-issuer-and-emit-dead-during-releaseACK",
    "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"_meta\":{\"progressToken\":7}}}",
    "callback": "dispatcher",
    "actions": [
      {
        "inside_dispatch_callback": "capture_authorized_view_request_params_span_OperationIssuer_and_emit; construct_lazy_span_read_without_execute; issue_valid_original_progress_value_and_common_default_result"
      },
      {
        "dispatch_callback_returns": true
      },
      {
        "source_reentry": "captured_release callback before releaseACK while outer Effect.scoped dispatch still unfinished"
      },
      {
        "execute_saved_read_effect": true
      },
      {
        "call_saved_operation_json": "existing_bounded_success_SourceValue_wire"
      },
      {
        "call_saved_operation_error": {
          "code": -32602,
          "fixedMessage": "Invalid tool arguments"
        }
      },
      {
        "execute_saved_emit_of_authentic_original_progress_value": "observe with Effect.exit; do not turn failed emit into release failure"
      },
      {
        "call_saved_view_with_foreign_revoked_Proxy": true
      },
      {
        "acknowledge_original_release": true
      }
    ],
    "expected": {
      "outer_authority_checks_at_dispatch_entry": 3,
      "escaped_read_authority_checks_delta": 0,
      "escaped_emit_authority_checks_delta": 0,
      "escaped_read_result": null,
      "escaped_issuer_json_result": null,
      "escaped_issuer_error_result": null,
      "escaped_emit_fixed_failure": "private_rpc_dispatch",
      "escaped_progress_sink_calls": 0,
      "successful_payload_materializations_delta": 0,
      "proxy_traps_delta": 0,
      "acquired": 1,
      "release_ACKs_after_handle_settles": 1,
      "cleanup_poisoned": false,
      "original_owned_result_can_continue_with_fresh_outer_authority": true
    }
  }
] as const;

interface ReadScene { readonly frame: string; readonly callback: string; readonly actions: readonly Readonly<Record<string, unknown>>[] }
interface ReadLiteral extends ReadScene { readonly case_id: string; readonly expected: Readonly<Record<string, unknown>> }
const readLiterals: readonly ReadLiteral[] = perReadLiterals;
/** Closed action stimulus only: no case IDs or expected fields enter any trusted port. */
function observeReadBoundary(scene: ReadScene): Effect.Effect<Readonly<Record<string, unknown>>, unknown> {
  return Effect.scoped(Effect.gen(function* () {
    const original = yield* Scope.make(); yield* Effect.addFinalizer(() => Scope.close(original, Exit.succeed(undefined)));
    const get = (key: string): unknown => scene.actions.find((action) => key in action)?.[key];
    const entered = yield* Deferred.make<void>(), resume = yield* Deferred.make<void>();
    let originalClosed = false, revoked = false, preparing = false, insideCallback = false;
    let checks = 0, acquired = 0, acknowledgments = 0, traps = 0, callbacksAfterClose = 0, sinkCalls = 0;
    let outerAtEntry = 0, reentryOuter = 0, replacementCalls = 0, reentered = false, heldCurrent = false;
    const phases: string[] = [], texts: string[] = [], variants: (string | null)[] = [], variantDeltas: number[] = [], lateResults: (string | null)[] = [];
    let secondPayloadReturned = false;
    let savedRead: Effect.Effect<string | null, FixedFailure> | undefined, savedView: AuthorizedRequestView | undefined, savedRequest: OwnedParsed | undefined, savedSpan: OwnedSpan | undefined, savedIssuer: OperationIssuer | undefined;
    let foreignSpan: OwnedSpan | undefined, savedEmit: ((value: OwnedJson) => Effect.Effect<void, FixedFailure>) | undefined, savedProgress: OwnedJson | undefined;
    let escapedRead: string | null = null, escapedJson: OwnedJson | null = null, escapedError: OwnedJson | null = null;
    let escapedReadDelta = 0, escapedEmitDelta = 0, escapedEmitFailure: string | null = null, escapedReadFailure: string | null = null, lateFailure: string | null = null;
    let postReadDelta = 0, cleanupPoisoned = false;
    const close = () => { Effect.runSync(Scope.close(original, Exit.succeed(undefined))); originalClosed = true; };
    const callback = () => { if (originalClosed) callbacksAfterClose++; };
    const throwing = new Proxy({}, Object.fromEntries(["get", "has", "ownKeys", "getPrototypeOf", "getOwnPropertyDescriptor"].map((key) => [key, () => { traps++; throw new Error(secret); }])));
    const revokedProxy = Proxy.revocable({}, {}); revokedProxy.revoke();
    const metadataResultWire = wire(constant({ capabilities: metadataInputs.capabilities_with_UI, instructions: metadataInputs.instructions, protocolVersion: metadataInputs.protocol_versions[3], serverInfo: metadataInputs.serverInfo }));
    const saveAndRead = (request: OwnedParsed, view: AuthorizedRequestView, issuer: OperationIssuer, emit?: (value: OwnedJson) => Effect.Effect<void, FixedFailure>) => Effect.gen(function* () {
      callback(); const md = view.inspect(request); assert.ok(md?.params);
      if (preparing) { foreignSpan = md.params; const result = issuer.json(defaultResultWire); assert.ok(result); return result; }
      outerAtEntry = checks; insideCallback = true;
      savedView = view; savedRequest = request; savedSpan = md.params; savedIssuer = issuer; savedEmit = emit;
      savedRead = view.spanText(request, md.params); // Lazy and deliberately reusable.
      if (get("inside_dispatch_callback")) {
        savedProgress = issuer.json(wire(constant({ jsonrpc: "2.0", method: "notifications/progress", params: { message: "Waiting for the paired source.", progress: 10, total: 120, progressToken: 7 } }))) ?? undefined;
        assert.ok(savedProgress);
      }
      const runRead = Effect.gen(function* () {
        const text = yield* savedRead!; if (text !== null) texts.push(text); return text;
      });
      const variantsInput = get("requests_and_spans") as readonly { readonly request: string; readonly span: string }[] | undefined;
      if (variantsInput) {
        assert.ok(foreignSpan);
        for (const variant of variantsInput) {
          const before = checks;
          const requestInput = variant.request.startsWith("foreign_Proxy") ? throwing : request;
          assert.ok(savedSpan);
          const spanInput = variant.span.startsWith("foreign_Proxy") ? throwing : variant.span === "foreign_revoked_Proxy" ? revokedProxy.proxy : variant.span === "own_span" ? savedSpan : foreignSpan;
          const text = yield* view.spanText(requestInput, spanInput); variants.push(text); variantDeltas.push(checks - before);
          if (text !== null) texts.push(text);
        }
      } else if (get("execute_same_read_effect") !== undefined) {
        yield* runRead; revoked = true;
        const second = yield* runRead; secondPayloadReturned = second !== null;
      } else if (get("construct_and_execute_read") !== undefined) { revoked = true; yield* runRead; }
      else if (get("execute_own_read_until") !== undefined) yield* runRead;
      else if (get("read") !== undefined) yield* runRead;
      // Other cases construct without execution and return a valid owned result.
      const result = issuer.json(scene.callback === "metadata" ? metadataResultWire : defaultResultWire); assert.ok(result); return result;
    }).pipe(Effect.ensuring(Effect.sync(() => { insideCallback = false; })));
    const inspectEscapes = (where: "authority" | "release") => Effect.gen(function* () {
      assert.ok(savedRead && savedView && savedRequest && savedSpan && savedIssuer);
      const before = checks, readExit = yield* Effect.exit(savedRead);
      escapedReadDelta = checks - before; escapedReadFailure = failureCode(readExit);
      if (Exit.isSuccess(readExit)) { escapedRead = readExit.value; if (readExit.value !== null) texts.push(readExit.value); }
      escapedJson = savedIssuer.json(defaultResultWire);
      escapedError = savedIssuer.error(-32602, where === "authority" ? "Unsupported MCP protocol version" : "Invalid tool arguments");
      assert.equal(yield* savedView.spanText(savedRequest, revokedProxy.proxy), null);
      if (where === "release") {
        assert.ok(savedEmit && savedProgress); const emitBefore = checks;
        const emission = yield* Effect.exit(savedEmit(savedProgress)); escapedEmitDelta = checks - emitBefore; escapedEmitFailure = failureCode(emission);
      }
    });
    const authority: TrustedFactoryInputs["authority"] = { check(request, phase, view) { return Effect.gen(function* () {
      callback(); checks++; assert.ok(view.inspect(request));
      if (!preparing && insideCallback) {
        phases.push(phase);
        if (get("execute_own_read_until") !== undefined && !heldCurrent) { heldCurrent = true; yield* Deferred.succeed(entered, undefined); yield* Deferred.await(resume); }
        if (revoked) return yield* Effect.fail(fault("private_rpc_authority"));
      }
      if (!preparing && !insideCallback && savedRead && get("reenter_from_original_authority") !== undefined && phase === "before_publication" && !reentered) {
        reentered = true; reentryOuter++; yield* inspectEscapes("authority");
      }
    }); } };
    const ports: TrustedFactoryInputs = {
      codec: {
        inspect(frame, issuer, view) { callback(); const raw = view.frameText(frame); assert.equal(typeof raw, "string"); const input = sourceInput(raw!); return input.disposition === "source_parse_error" ? issuer.sourceParseError(frame) : issuer.inspection(input.primitive_metadata_wire, frame); },
        serialize(request, reply, issuer, view) {
          callback(); const body = view.inspectReply(reply); assert.ok(body);
          const text = body.kind === "success" ? '{"id":' + body.idCanonicalEncoded + ',"jsonrpc":"2.0","result":' + render(view.readJson(body.result)) + '}' : body.kind === "error" ? '{"error":{"code":' + BigInt(body.code).toString() + ',"message":' + q(body.fixedMessage) + '},"id":' + body.idCanonicalEncoded + ',"jsonrpc":"2.0"}' : render(view.readJson(body.notification));
          return issuer.encoded(text, request);
        },
      }, authority,
      dispatcher: {
        acquire: () => Effect.sync(() => { callback(); acquired++; return Object.freeze({ syntheticResource: true }); }),
        release: () => Effect.gen(function* () { if (!preparing && get("source_reentry") !== undefined) yield* inspectEscapes("release"); acknowledgments++; }),
        dispatch: (request, _lease, emit, view, issuer) => saveAndRead(request, view, issuer, emit),
      },
      metadata: { describe: (request, view, issuer) => saveAndRead(request, view, issuer) },
      progress: { publish: () => Effect.sync(() => { callback(); sinkCalls++; }) },
    };
    const envelope = yield* createRpcEnvelope(ports).pipe(Effect.provideService(Scope.Scope, original));
    const session = yield* envelope.open().pipe(Effect.provideService(Scope.Scope, original));
    if (get("requests_and_spans") !== undefined) {
      preparing = true; const other = yield* createRpcEnvelope(ports).pipe(Effect.provideService(Scope.Scope, original));
      const otherSession = yield* other.open().pipe(Effect.provideService(Scope.Scope, original));
      yield* other.handle(otherSession, scene.frame); preparing = false; checks = 0; acquired = 0; acknowledgments = 0;
    }
    let exit: Exit.Exit<OwnedOutput | null, FixedFailure>;
    if (get("execute_own_read_until") !== undefined) {
      const child = yield* Effect.forkChild(envelope.handle(session, scene.frame)); yield* Deferred.await(entered);
      close(); yield* Deferred.succeed(resume, undefined); exit = yield* Fiber.await(child);
    } else exit = yield* Effect.exit(envelope.handle(session, scene.frame));
    const initialFailure = failureCode(exit), originalContinues = Exit.isSuccess(exit) && exit.value !== null;
    const outputCount = originalContinues ? 1 : 0;
    if (get("execute_retained_effect_in_fresh_Scope_and_reprovided_authority") !== undefined) {
      assert.ok(savedRead); const before = checks;
      authority.check = () => Effect.sync(() => { replacementCalls++; }); // Original factory captured prior callback.
      const fresh = yield* Scope.make(); yield* Effect.addFinalizer(() => Scope.close(fresh, Exit.succeed(undefined)));
      const late = yield* Effect.exit(savedRead.pipe(Effect.provideService(Scope.Scope, fresh))); lateFailure = failureCode(late); if (Exit.isSuccess(late)) { lateResults.push(late.value); if (late.value !== null) texts.push(late.value); }
      close(); const later = yield* Effect.exit(savedRead.pipe(Effect.provideService(Scope.Scope, fresh))); if (lateFailure === null) lateFailure = failureCode(later); if (Exit.isSuccess(later)) { lateResults.push(later.value); if (later.value !== null) texts.push(later.value); }
      postReadDelta = checks - before;
    }
    if (get("source_reentry") !== undefined) {
      const followup = yield* Effect.exit(envelope.handle(session, '{"jsonrpc":"2.0","id":2,"method":"ping"}'));
      cleanupPoisoned = failureCode(followup) === "private_rpc_cleanup"; assert.ok(Exit.isSuccess(followup));
    }
    return {
      outer_authority_checks_at_callback_entry: outerAtEntry, outer_authority_checks_at_metadata_entry: outerAtEntry, outer_authority_checks_at_dispatch_entry: outerAtEntry,
      read_authority_checks_delta: phases.length, read_authority_checks_delta_inside_callback: phases.length, read_authority_phases: [...phases], successful_payload_materializations_delta: texts.length, returned_span_texts: [...texts], second_payload_returned: secondPayloadReturned,
      proxy_traps_delta: traps, acquired, release_ACKs_after_handle_settles: acknowledgments, release_ACKs: acknowledgments, fixed_failure: initialFailure, escaped_callbacks: callbacksAfterClose,
      output_or_delivery_after_revoke: outputCount + sinkCalls, output_or_delivery_after_close: outputCount + sinkCalls, new_trusted_callbacks_entered_after_close: callbacksAfterClose,
      per_variant_read_authority_checks_delta: variantDeltas, per_variant_results: variants, no_foreign_properties_observed: traps === 0,
      post_callback_read_authority_checks_delta: postReadDelta, replacement_authority_calls: replacementCalls, late_results: lateResults, late_fixed_failure: lateFailure, revival: lateResults.some((value) => value !== null) || replacementCalls !== 0,
      reentry_authority_callback_is_outer_check: reentryOuter, escaped_read_authority_checks_delta: escapedReadDelta, escaped_read_result: escapedRead, escaped_issuer_json_result: escapedJson, escaped_issuer_error_result: escapedError, fixed_failure_for_escaped_read: escapedReadFailure,
      original_metadata_result_can_continue_with_fresh_outer_authority: originalContinues, original_owned_result_can_continue_with_fresh_outer_authority: originalContinues,
      escaped_emit_authority_checks_delta: escapedEmitDelta, escaped_emit_fixed_failure: escapedEmitFailure, escaped_progress_sink_calls: sinkCalls, cleanup_poisoned: cleanupPoisoned,
    };
  }));
}
for (const literal of readLiterals) test(`owned lazy span/callback boundary ${literal.case_id}`, { timeout: 20000 }, async () => {
  const actual = await Effect.runPromise(observeReadBoundary({ frame: literal.frame, callback: literal.callback, actions: literal.actions }));
  for (const [key, value] of Object.entries(literal.expected)) assert.deepEqual(actual[key], value, key);
});

// Exact independently frozen four progress-read scenes; expectations never enter ports.
const progressReadLiterals = [
  {
    "case_id": "progress-owned-delayed-read-current-permitted",
    "stimulus": {
      "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
      "source_input": {
        "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
        "frame_sha256": "d4c84ec7ec8d01340ac4ebd35ff74ab6315d4c35b1944f5cf59beebc907b4be3",
        "disposition": "parsed",
        "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":124},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":122}}",
        "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"unsigned_integer\",\"decimal\":\"7\"}]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
      },
      "dispatcher": {
        "result_source_wire": "{\"kind\":\"object\",\"entries\":[[\"content\",[{\"kind\":\"object\",\"entries\":[[\"text\",\"{\\\"ready\\\":true}\"],[\"type\",\"text\"]]}]],[\"isError\",false]]}",
        "emit_count": 1,
        "fixed_progress": {
          "progress": 10,
          "total": 120,
          "message": "Waiting for the paired source."
        }
      },
      "native_network_source_IO": false,
      "authority": "captured trusted fake; grant permitted initially, original Scope live; no caller grant flags",
      "ownership": "One owned acquired resource; release acknowledged exactly once, await finalizer before handle completes",
      "actions": [
        {
          "sink": "capture own output/view; signal real Deferred entered; await real Deferred proceed"
        },
        {
          "controller": "Scope remains live, grant permitted; complete proceed"
        },
        {
          "sink": "yield SAME lazy encodedText(ownOutput) Effect; then publish observed text exactly once"
        }
      ]
    },
    "expected": {
      "dispatch_calls": 1,
      "allocation_calls": 1,
      "release_attempts": 1,
      "release_ACKs": 1,
      "sink_calls": 1,
      "source_calls": 0,
      "forbidden_IO_calls": 0,
      "property_traps": 0,
      "provider_cause_disclosed": false,
      "kind": "response",
      "private_failure": null,
      "progress_read_results": [
        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"message\":\"Waiting for the paired source.\",\"progress\":10,\"progressToken\":7,\"total\":120}}"
      ],
      "progress_publications": 1,
      "progress_utf8": [
        "{\"jsonrpc\":\"2.0\",\"method\":\"notifications/progress\",\"params\":{\"message\":\"Waiting for the paired source.\",\"progress\":10,\"progressToken\":7,\"total\":120}}"
      ],
      "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
      "response_publications": 1,
      "response_LF": false
    }
  },
  {
    "case_id": "progress-delayed-read-revoke-scope-alive",
    "stimulus": {
      "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
      "source_input": {
        "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
        "frame_sha256": "d4c84ec7ec8d01340ac4ebd35ff74ab6315d4c35b1944f5cf59beebc907b4be3",
        "disposition": "parsed",
        "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":124},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":122}}",
        "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"unsigned_integer\",\"decimal\":\"7\"}]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
      },
      "dispatcher": {
        "result_source_wire": "{\"kind\":\"object\",\"entries\":[[\"content\",[{\"kind\":\"object\",\"entries\":[[\"text\",\"{\\\"ready\\\":true}\"],[\"type\",\"text\"]]}]],[\"isError\",false]]}",
        "emit_count": 1,
        "fixed_progress": {
          "progress": 10,
          "total": 120,
          "message": "Waiting for the paired source."
        }
      },
      "native_network_source_IO": false,
      "authority": "captured trusted fake; grant permitted initially, original Scope live; no caller grant flags",
      "ownership": "One owned acquired resource; release acknowledged exactly once, await finalizer before handle completes",
      "actions": [
        {
          "sink": "capture own output/view; signal real Deferred entered; await real Deferred proceed"
        },
        {
          "controller": "revoke trusted current grant without closing Scope; complete proceed"
        },
        {
          "sink": "yield lazy encodedText(ownOutput) Effect; fresh captured before_progress check must fail before text"
        },
        {
          "release": "real finalizer ACK observed before handle returns failure"
        }
      ]
    },
    "expected": {
      "dispatch_calls": 1,
      "allocation_calls": 1,
      "release_attempts": 1,
      "release_ACKs": 1,
      "sink_calls": 1,
      "source_calls": 0,
      "forbidden_IO_calls": 0,
      "property_traps": 0,
      "provider_cause_disclosed": false,
      "kind": "private_failure",
      "private_failure": "private_rpc_authority",
      "text_observations": [],
      "progress_publications": 0,
      "response_publications": 0,
      "response_utf8": null,
      "response_LF": false,
      "original_scope_remained_live_until_cleanup": true
    }
  },
  {
    "case_id": "progress-read-current-check-closes-original-scope",
    "stimulus": {
      "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
      "source_input": {
        "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
        "frame_sha256": "d4c84ec7ec8d01340ac4ebd35ff74ab6315d4c35b1944f5cf59beebc907b4be3",
        "disposition": "parsed",
        "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":124},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":122}}",
        "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"unsigned_integer\",\"decimal\":\"7\"}]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
      },
      "dispatcher": {
        "result_source_wire": "{\"kind\":\"object\",\"entries\":[[\"content\",[{\"kind\":\"object\",\"entries\":[[\"text\",\"{\\\"ready\\\":true}\"],[\"type\",\"text\"]]}]],[\"isError\",false]]}",
        "emit_count": 1,
        "fixed_progress": {
          "progress": 10,
          "total": 120,
          "message": "Waiting for the paired source."
        }
      },
      "native_network_source_IO": false,
      "authority": "captured trusted fake; grant permitted initially, original Scope live; no caller grant flags",
      "ownership": "One owned acquired resource; release acknowledged exactly once, await finalizer before handle completes",
      "actions": [
        {
          "sink": "yield lazy own encodedText Effect after captured own output/view"
        },
        {
          "authority_on_this_read": "actual Scope.close original Scope, return normally; outer captured current/life recheck wins before slice"
        },
        {
          "sink": "no text or publication on failed read"
        },
        {
          "release": "ACK permitted as cleanup, exactly once; no new metadata/dispatch/codec/sink callback after closure"
        }
      ]
    },
    "expected": {
      "dispatch_calls": 1,
      "allocation_calls": 1,
      "release_attempts": 1,
      "release_ACKs": 1,
      "sink_calls": 1,
      "source_calls": 0,
      "forbidden_IO_calls": 0,
      "property_traps": 0,
      "provider_cause_disclosed": false,
      "kind": "private_failure",
      "private_failure": "owned_handoff_closed",
      "text_observations": [],
      "progress_publications": 0,
      "response_publications": 0,
      "response_utf8": null,
      "response_LF": false,
      "new_noncleanup_callbacks_after_close": 0
    }
  },
  {
    "case_id": "progress-escaped-sink-view-dead-at-postcurrent-and-release",
    "stimulus": {
      "frame": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
      "source_input": {
        "frame_utf8": "{\"jsonrpc\":\"2.0\",\"id\":1,\"method\":\"tools/call\",\"params\":{\"name\":\"healthmd_status\",\"arguments\":{},\"_meta\":{\"progressToken\":7}}}",
        "frame_sha256": "d4c84ec7ec8d01340ac4ebd35ff74ab6315d4c35b1944f5cf59beebc907b4be3",
        "disposition": "parsed",
        "primitive_metadata_wire": "{\"rootObject\":true,\"version2\":true,\"id\":{\"present\":true,\"scalar\":\"unsigned_integer\",\"canonicalEncoded\":\"1\",\"validI64OrString\":true},\"method\":\"tools/call\",\"params\":{\"start\":55,\"end\":124},\"paramsDefaulted\":false,\"progressToken\":{\"start\":121,\"end\":122}}",
        "source_value_wire": "{\"kind\":\"object\",\"entries\":[[\"id\",{\"kind\":\"unsigned_integer\",\"decimal\":\"1\"}],[\"jsonrpc\",\"2.0\"],[\"method\",\"tools/call\"],[\"params\",{\"kind\":\"object\",\"entries\":[[\"_meta\",{\"kind\":\"object\",\"entries\":[[\"progressToken\",{\"kind\":\"unsigned_integer\",\"decimal\":\"7\"}]]}],[\"arguments\",{\"kind\":\"object\",\"entries\":[]}],[\"name\",\"healthmd_status\"]]}]]}"
      },
      "dispatcher": {
        "result_source_wire": "{\"kind\":\"object\",\"entries\":[[\"content\",[{\"kind\":\"object\",\"entries\":[[\"text\",\"{\\\"ready\\\":true}\"],[\"type\",\"text\"]]}]],[\"isError\",false]]}",
        "emit_count": 1,
        "fixed_progress": {
          "progress": 10,
          "total": 120,
          "message": "Waiting for the paired source."
        }
      },
      "native_network_source_IO": false,
      "authority": "captured trusted fake; grant permitted initially, original Scope live; no caller grant flags",
      "ownership": "One owned acquired resource; release acknowledged exactly once, await finalizer before handle completes",
      "actions": [
        {
          "sink": "save own output/view and lazy encodedText Effect; return normally without reading or publishing"
        },
        {
          "post_callback_authority": "after sink Effect has returned but dispatch callback is still active, yield saved Effect; must return null before current callbacks or text/property access"
        },
        {
          "release_callback": "yield saved Effect again before release ACK; must return null before current callbacks or text/property access"
        },
        {
          "scope": "original Scope and grant remain live/permitted; normal response follows cleanup"
        }
      ]
    },
    "expected": {
      "dispatch_calls": 1,
      "allocation_calls": 1,
      "release_attempts": 1,
      "release_ACKs": 1,
      "sink_calls": 1,
      "source_calls": 0,
      "forbidden_IO_calls": 0,
      "property_traps": 0,
      "provider_cause_disclosed": false,
      "kind": "response",
      "private_failure": null,
      "escaped_read_results": [
        null,
        null
      ],
      "authority_calls_during_escaped_reads": 0,
      "text_observations": [],
      "progress_publications": 0,
      "response_utf8": "{\"id\":1,\"jsonrpc\":\"2.0\",\"result\":{\"content\":[{\"text\":\"{\\\"ready\\\":true}\",\"type\":\"text\"}],\"isError\":false}}",
      "response_publications": 1,
      "response_LF": false,
      "escaped_reads_do_not_revive_callback": true
    }
  }
] as const;
interface ProgressReadScene {
  readonly frame: string;
  readonly source_input: FrameInput;
  readonly dispatcher: { readonly result_source_wire: string; readonly emit_count: number; readonly fixed_progress: Readonly<Record<string, unknown>> };
  readonly actions: readonly Readonly<Record<string, string>>[];
}
/** Action-only Effect driver; no case ID or expected result reaches an issuer or trusted port. */
function observeProgressRead(scene: ProgressReadScene): Effect.Effect<Readonly<Record<string, unknown>>, unknown> {
  return Effect.scoped(Effect.gen(function* () {
    assert.deepEqual(sourceInput(scene.frame), scene.source_input, "the approved85 descriptor corpus is the only parser stimulus");
    const original = yield* Scope.make(); yield* Effect.addFinalizer(() => Scope.close(original, Exit.succeed(undefined)));
    const entered = yield* Deferred.make<void>(), proceed = yield* Deferred.make<void>();
    const action = (key: string) => scene.actions.find((row) => key in row)?.[key];
    const delayed = action("controller") !== undefined, revoke = action("controller")?.startsWith("revoke") === true;
    const closeDuringRead = action("authority_on_this_read") !== undefined, escaping = action("post_callback_authority") !== undefined;
    let originalClosed = false, revoked = false, inSink = false, reading = false, postReadDone = false;
    let dispatchCalls = 0, allocationCalls = 0, releaseAttempts = 0, releaseACKs = 0, sinkCalls = 0, checks = 0, traps = 0, callbacksAfterClose = 0, escapedCheckDelta = 0;
    const texts: string[] = [], escapedReads: (string | null)[] = [];
    let saved: Effect.Effect<string | null, FixedFailure> | undefined;
    let savedView: OwnedOutputView | undefined, savedOutput: OwnedOutput | undefined;
    const callback = () => { if (originalClosed) callbacksAfterClose++; };
    const close = () => { Effect.runSync(Scope.close(original, Exit.succeed(undefined))); originalClosed = true; };
    const throwing = new Proxy({}, Object.fromEntries(["get", "has", "ownKeys", "getPrototypeOf", "getOwnPropertyDescriptor"].map((key) => [key, () => { traps++; throw new Error(secret); }])));
    const dead = Proxy.revocable({}, {}); dead.revoke();
    const escaped = () => Effect.gen(function* () {
      assert.ok(saved && savedView && savedOutput); const before = checks;
      const text = yield* saved; escapedReads.push(text); if (text !== null) texts.push(text);
      escapedCheckDelta += checks - before;
    });
    const ports: TrustedFactoryInputs = {
      codec: {
        inspect(frame, issuer, view) { callback(); const raw = view.frameText(frame); assert.equal(typeof raw, "string"); const input = sourceInput(raw!); return input.disposition === "source_parse_error" ? issuer.sourceParseError(frame) : issuer.inspection(input.primitive_metadata_wire, frame); },
        serialize(request, reply, issuer, view) {
          callback(); const body = view.inspectReply(reply); assert.ok(body);
          const text = body.kind === "success" ? '{"id":' + body.idCanonicalEncoded + ',"jsonrpc":"2.0","result":' + render(view.readJson(body.result)) + '}' : body.kind === "error" ? '{"error":{"code":' + BigInt(body.code).toString() + ',"message":' + q(body.fixedMessage) + '},"id":' + body.idCanonicalEncoded + ',"jsonrpc":"2.0"}' : render(view.readJson(body.notification));
          return issuer.encoded(text, request);
        },
      },
      authority: { check(request, phase, view) { return Effect.gen(function* () {
        callback(); checks++; assert.ok(view.inspect(request));
        if (reading && phase === "before_progress") {
          if (closeDuringRead) close();
          if (revoked) return yield* Effect.fail(fault("private_rpc_authority"));
        }
        if (escaping && saved && !inSink && !postReadDone && phase === "before_progress") { postReadDone = true; yield* escaped(); }
      }); } },
      dispatcher: {
        acquire: () => Effect.sync(() => { callback(); allocationCalls++; return Object.freeze({ syntheticResource: true }); }),
        release: () => Effect.gen(function* () { releaseAttempts++; if (escaping) yield* escaped(); releaseACKs++; }),
        dispatch(request, _lease, emit, view, issuer) { return Effect.gen(function* () {
          callback(); dispatchCalls++; assert.ok(view.inspect(request));
          const notification = issuer.json(wire(constant({ jsonrpc: "2.0", method: "notifications/progress", params: { ...scene.dispatcher.fixed_progress, progressToken: 7 } }))); assert.ok(notification);
          for (let i = 0; i < scene.dispatcher.emit_count; i++) yield* emit(notification);
          const result = issuer.json(scene.dispatcher.result_source_wire); assert.ok(result); return result;
        }); },
      },
      metadata: { describe: () => Effect.die(new Error("metadata is outside these operation stimuli")) },
      progress: { publish(output, view) { return Effect.gen(function* () {
        callback(); sinkCalls++; inSink = true; savedView = view; savedOutput = output;
        saved = view.encodedText(output); // Construction is lazy; controller acts before evaluation.
        const before = checks;
        assert.equal(yield* view.encodedText(throwing), null); assert.equal(yield* view.encodedText(dead.proxy), null);
        assert.equal(checks - before, 0, "unknown outputs perform zero authority callbacks");
        if (escaping) return;
        if (delayed) { yield* Deferred.succeed(entered, undefined); yield* Deferred.await(proceed); }
        reading = true;
        const text = yield* saved.pipe(Effect.ensuring(Effect.sync(() => { reading = false; })));
        if (text !== null) texts.push(text);
      }).pipe(Effect.ensuring(Effect.sync(() => { inSink = false; }))); } },
    };
    const envelope = yield* createRpcEnvelope(ports).pipe(Effect.provideService(Scope.Scope, original));
    const session = yield* envelope.open().pipe(Effect.provideService(Scope.Scope, original));
    let exit: Exit.Exit<OwnedOutput | null, FixedFailure>;
    if (delayed) {
      const child = yield* Effect.forkChild(envelope.handle(session, scene.frame)); yield* Deferred.await(entered);
      revoked = revoke; yield* Deferred.succeed(proceed, undefined); exit = yield* Fiber.await(child);
    } else exit = yield* Effect.exit(envelope.handle(session, scene.frame));
    const privateFailure = failureCode(exit);
    let response: string | null = null;
    if (Exit.isSuccess(exit) && exit.value !== null) response = yield* envelope.encode(session, exit.value);
    return {
      dispatch_calls: dispatchCalls, allocation_calls: allocationCalls, release_attempts: releaseAttempts, release_ACKs: releaseACKs, sink_calls: sinkCalls,
      source_calls: 0, forbidden_IO_calls: 0, property_traps: traps, provider_cause_disclosed: false,
      kind: privateFailure === null ? "response" : "private_failure", private_failure: privateFailure,
      progress_read_results: [...texts], text_observations: [...texts], progress_publications: texts.length, progress_utf8: [...texts],
      response_utf8: response, response_publications: response === null ? 0 : 1, response_LF: response?.endsWith("\n") ?? false,
      original_scope_remained_live_until_cleanup: !originalClosed, new_noncleanup_callbacks_after_close: callbacksAfterClose,
      escaped_read_results: escapedReads, authority_calls_during_escaped_reads: escapedCheckDelta,
      escaped_reads_do_not_revive_callback: escapedReads.every((text) => text === null) && escapedCheckDelta === 0,
    };
  }));
}
for (const literal of progressReadLiterals) test(`owned lazy progress/callback boundary ${literal.case_id}`, { timeout: 20000 }, async () => {
  const actual = await Effect.runPromise(observeProgressRead(literal.stimulus));
  for (const [key, value] of Object.entries(literal.expected)) assert.deepEqual(actual[key], value, key);
});

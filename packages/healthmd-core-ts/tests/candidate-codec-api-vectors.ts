/** Stage1 frozen facade contract/literals. No candidate execution or expected-output generation. */
import type { ExactJsonNumberParser } from "../src/serialization/exact-json-number-parser.js";
import type { ExactJsonValueFactory, ExactJsonValueFailure } from "../src/serialization/exact-json-value.js";
import type { CanonicalJsonSerializer } from "../src/serialization/canonical-json.js";
import type { ExactJsonNumberResult } from "../src/serialization/exact-json-numbers.js";
import type * as Result from "effect/Result";
export interface CandidateCodecApi {
  readonly createExactJsonNumberParser: () => ExactJsonNumberParser;
  readonly createExactJsonCodec: () => ExactJsonValueFactory;
  readonly createCanonicalJsonSerializer: (codec: unknown, readerToken: unknown) => Result.Result<CanonicalJsonSerializer, ExactJsonValueFailure>;
  readonly serializeExactJsonNumber: (representation: unknown, payload: unknown) => ExactJsonNumberResult;
}
export const candidateCodecApiContract = {
  "literal_package": "@healthmd/core-ts/candidate/codecs",
  "literal_entry": {
    "types": "./dist/core/serialization/index.d.ts",
    "import": "./dist/core/serialization/index.js"
  },
  "runtime_named_exports": {
    "createExactJsonNumberParser": "./exact-json-number-parser.js",
    "createExactJsonCodec": "./exact-json-value.js",
    "createCanonicalJsonSerializer": "./canonical-json.js",
    "serializeExactJsonNumber": "./exact-json-numbers.js"
  },
  "type_named_exports": {
    "OwnedJsonNumber": "./exact-json-number-parser.js",
    "SourceNumber": "./exact-json-number-parser.js",
    "ExactJsonNumberParser": "./exact-json-number-parser.js",
    "ExactJsonNumberFailure": "./exact-json-numbers.js",
    "ExactJsonNumberResult": "./exact-json-numbers.js",
    "OwnedJsonValue": "./exact-json-value.js",
    "ExactJsonValueFailure": "./exact-json-value.js",
    "OwnedJsonValueCodec": "./exact-json-value.js",
    "ExactJsonValueFactory": "./exact-json-value.js",
    "CanonicalJsonSerializer": "./canonical-json.js"
  },
  "original_package_exports": {
    ".": {
      "types": "./dist/core/index.d.ts",
      "import": "./dist/core/index.js"
    },
    "./host-interfaces": {
      "types": "./dist/core/host-interfaces/capabilities.d.ts",
      "import": "./dist/core/host-interfaces/capabilities.js"
    },
    "./candidate/catalog": {
      "types": "./dist/core/operations/catalog.d.ts",
      "import": "./dist/core/operations/catalog.js"
    },
    "./candidate/normalize": {
      "types": "./dist/core/operations/normalize.d.ts",
      "import": "./dist/core/operations/normalize.js"
    },
    "./candidate/query": {
      "types": "./dist/core/operations/query.d.ts",
      "import": "./dist/core/operations/query.js"
    },
    "./candidate/registry": {
      "types": "./dist/core/contracts/registry.d.ts",
      "import": "./dist/core/contracts/registry.js"
    }
  },
  "original_root_index_utf8": "export { CandidateSession, inspectCandidate } from \"./host-interfaces/capabilities.js\";\nexport type { CandidateResource } from \"./host-interfaces/capabilities.js\";\nexport { CapabilityFailed, CapabilityUnavailable } from \"./host-interfaces/faults.js\";\nexport type { CapabilityFault } from \"./host-interfaces/faults.js\";\n",
  "forbidden_named_exports": [
    "captureExactJsonValueReader",
    "CapturedExactJsonValueReader",
    "ExactJsonValueNode",
    "SourceNumericValue",
    "OwnedJsonValueReaderToken"
  ],
  "forbidden_package_paths": [
    "@healthmd/core-ts/candidate/codecs/*",
    "@healthmd/core-ts/serialization/exact-json-value",
    "@healthmd/core-ts/dist/core/serialization/exact-json-value.js",
    "@healthmd/core-ts/candidate/codecs/reader"
  ],
  "declarations": {
    "createExactJsonNumberParser": "() => ExactJsonNumberParser",
    "createExactJsonCodec": "() => ExactJsonValueFactory",
    "createCanonicalJsonSerializer": "(codec: unknown, readerToken: unknown) => Result.Result<CanonicalJsonSerializer, ExactJsonValueFailure>",
    "serializeExactJsonNumber": "(representation: unknown, payload: unknown) => ExactJsonNumberResult",
    "ExactJsonNumberParser.parse": "(representation: unknown, payload: unknown) => Result.Result<OwnedJsonNumber, ExactJsonNumberFailure>",
    "ExactJsonNumberParser.read": "(handle: unknown) => Result.Result<SourceNumber, ExactJsonNumberFailure>",
    "SourceNumber": "{ readonly class: \"i64\" | \"u64\"; readonly decimal: string } | { readonly class: \"f64\"; readonly bits: string }",
    "OwnedJsonValueCodec.parse": "(representation: unknown, payload: unknown) => Result.Result<OwnedJsonValue, ExactJsonValueFailure>",
    "ExactJsonValueFactory": "{ readonly codec: OwnedJsonValueCodec; readonly readerToken: original opaque OwnedJsonValueReaderToken }",
    "CanonicalJsonSerializer.encode": "(handle: unknown, policy: unknown) => Result.Result<Uint8Array, ExactJsonValueFailure>",
    "ExactJsonNumberResult": "Result.Result<Uint8Array, ExactJsonNumberFailure>",
    "ExactJsonNumberFailure": "{ readonly _tag: \"ExactJsonNumberFailure\"; readonly code: \"invalid_json_number\" }",
    "ExactJsonValueFailure": "{ readonly _tag: \"ExactJsonValueFailure\"; readonly code: \"invalid_json_value\" }"
  },
  "declaration_graph_policy": "Original nominal unique-symbol declarations are retained by their original modules. ExactJsonValueFactory.readerToken transitively refers to the original opaque token type, which is NOT a named facade type export. Its only facade use is the authentic samefactory serializer constructor argument. No wrapper, AST/reader export, injected visitor, rebranding, algorithm or Scope/source/grant authority. NumberFailure is selected from original scalar module; structurally identical parser failure is not a second facade name.",
  "source_graph_policy": "Exactly four relative original modules and named reexports only; effect/Result exists only in original modules/declarations, one physical Effect dependency. No facade execution side effect or imports from test/host/Node/native; no wildcard/root-index mutation.",
  "bounds": "Original parser/serializer/scalar budgets retained exactly; facade adds no parsing, decoding, numeric conversion, byte allocation, policy or budget. Tests use original stimuli, never expected/case-ID keyed fake codecs.",
  "prospective_authority": "Current accepted 53 input /32 core module outputs; prospective 56/34 adds facade source/test/vector and facade JS/d.ts, plus separately already present Catalog96 data-only input. Not consumer/cohort admission. Historical 43/26 remains immutable."
} as const;
export const candidateCodecApiVectors = [
  {
    "case_id": "codec-export-literal",
    "input": "@healthmd/core-ts/candidate/codecs",
    "expected": {
      "present": true,
      "wildcard": false
    },
    "source_basis": "proposed private facade",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "codec-root-retained",
    "input": "@healthmd/core-ts",
    "expected": {
      "original_exports_unchanged": true
    },
    "source_basis": "src/index.ts immutable",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "codec-identity-single",
    "input": {
      "harness": "facade scalar vs original scalar on all accepted frozen numbers"
    },
    "expected": {
      "bytes_equal": true,
      "one_effect": true,
      "duplicate_renderer": false
    },
    "source_basis": "accepted scalar authority",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "facade-runtime-names",
    "group": "manifest",
    "input": {
      "inspect": "runtime namespace own named exports"
    },
    "expected": {
      "names": [
        "createCanonicalJsonSerializer",
        "createExactJsonCodec",
        "createExactJsonNumberParser",
        "serializeExactJsonNumber"
      ],
      "default": false,
      "additional_names": []
    },
    "source_basis": "Four accepted original function declarations and bounded facade outcome"
  },
  {
    "case_id": "facade-type-whitelist",
    "group": "declarations",
    "input": {
      "inspect": "named type exports"
    },
    "expected": {
      "names": [
        "CanonicalJsonSerializer",
        "ExactJsonNumberFailure",
        "ExactJsonNumberParser",
        "ExactJsonNumberResult",
        "ExactJsonValueFactory",
        "ExactJsonValueFailure",
        "OwnedJsonNumber",
        "OwnedJsonValue",
        "OwnedJsonValueCodec",
        "SourceNumber"
      ],
      "additional_names": []
    },
    "source_basis": "Closed whitelist; original opaque nominal types retained, no reader/AST"
  },
  {
    "case_id": "identity-createExactJsonNumberParser",
    "group": "identity",
    "input": {
      "facade": "createExactJsonNumberParser",
      "original_module": "./exact-json-number-parser.js"
    },
    "expected": {
      "same_function_reference": true,
      "wrapper": false,
      "duplicate_algorithm": false
    },
    "source_basis": "Original accepted function object; explicit reexport has ESM identity"
  },
  {
    "case_id": "identity-createExactJsonCodec",
    "group": "identity",
    "input": {
      "facade": "createExactJsonCodec",
      "original_module": "./exact-json-value.js"
    },
    "expected": {
      "same_function_reference": true,
      "wrapper": false,
      "duplicate_algorithm": false
    },
    "source_basis": "Original accepted function object; explicit reexport has ESM identity"
  },
  {
    "case_id": "identity-createCanonicalJsonSerializer",
    "group": "identity",
    "input": {
      "facade": "createCanonicalJsonSerializer",
      "original_module": "./canonical-json.js"
    },
    "expected": {
      "same_function_reference": true,
      "wrapper": false,
      "duplicate_algorithm": false
    },
    "source_basis": "Original accepted function object; explicit reexport has ESM identity"
  },
  {
    "case_id": "identity-serializeExactJsonNumber",
    "group": "identity",
    "input": {
      "facade": "serializeExactJsonNumber",
      "original_module": "./exact-json-numbers.js"
    },
    "expected": {
      "same_function_reference": true,
      "wrapper": false,
      "duplicate_algorithm": false
    },
    "source_basis": "Original accepted function object; explicit reexport has ESM identity"
  },
  {
    "case_id": "type-OwnedJsonNumber",
    "group": "declarations",
    "input": {
      "name": "OwnedJsonNumber",
      "original_module": "./exact-json-number-parser.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-SourceNumber",
    "group": "declarations",
    "input": {
      "name": "SourceNumber",
      "original_module": "./exact-json-number-parser.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-ExactJsonNumberParser",
    "group": "declarations",
    "input": {
      "name": "ExactJsonNumberParser",
      "original_module": "./exact-json-number-parser.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-ExactJsonNumberFailure",
    "group": "declarations",
    "input": {
      "name": "ExactJsonNumberFailure",
      "original_module": "./exact-json-numbers.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-ExactJsonNumberResult",
    "group": "declarations",
    "input": {
      "name": "ExactJsonNumberResult",
      "original_module": "./exact-json-numbers.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-OwnedJsonValue",
    "group": "declarations",
    "input": {
      "name": "OwnedJsonValue",
      "original_module": "./exact-json-value.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-ExactJsonValueFailure",
    "group": "declarations",
    "input": {
      "name": "ExactJsonValueFailure",
      "original_module": "./exact-json-value.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-OwnedJsonValueCodec",
    "group": "declarations",
    "input": {
      "name": "OwnedJsonValueCodec",
      "original_module": "./exact-json-value.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-ExactJsonValueFactory",
    "group": "declarations",
    "input": {
      "name": "ExactJsonValueFactory",
      "original_module": "./exact-json-value.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "type-CanonicalJsonSerializer",
    "group": "declarations",
    "input": {
      "name": "CanonicalJsonSerializer",
      "original_module": "./canonical-json.js"
    },
    "expected": {
      "original_type_reexport": true,
      "assignable_both_directions": true,
      "fresh_brand": false
    },
    "source_basis": "Original exported declarations; source inspection plus future compile witness"
  },
  {
    "case_id": "no-export-captureExactJsonValueReader",
    "group": "manifest",
    "input": {
      "name": "captureExactJsonValueReader"
    },
    "expected": {
      "runtime_own_property": false,
      "named_type_export": false
    },
    "source_basis": "Deliberately excluded facade surface; transitive nominal token declaration is allowed"
  },
  {
    "case_id": "no-export-CapturedExactJsonValueReader",
    "group": "manifest",
    "input": {
      "name": "CapturedExactJsonValueReader"
    },
    "expected": {
      "runtime_own_property": false,
      "named_type_export": false
    },
    "source_basis": "Deliberately excluded facade surface; transitive nominal token declaration is allowed"
  },
  {
    "case_id": "no-export-ExactJsonValueNode",
    "group": "manifest",
    "input": {
      "name": "ExactJsonValueNode"
    },
    "expected": {
      "runtime_own_property": false,
      "named_type_export": false
    },
    "source_basis": "Deliberately excluded facade surface; transitive nominal token declaration is allowed"
  },
  {
    "case_id": "no-export-SourceNumericValue",
    "group": "manifest",
    "input": {
      "name": "SourceNumericValue"
    },
    "expected": {
      "runtime_own_property": false,
      "named_type_export": false
    },
    "source_basis": "Deliberately excluded facade surface; transitive nominal token declaration is allowed"
  },
  {
    "case_id": "no-export-OwnedJsonValueReaderToken",
    "group": "manifest",
    "input": {
      "name": "OwnedJsonValueReaderToken"
    },
    "expected": {
      "runtime_own_property": false,
      "named_type_export": false
    },
    "source_basis": "Deliberately excluded facade surface; transitive nominal token declaration is allowed"
  },
  {
    "case_id": "no-package-path-0",
    "group": "manifest",
    "input": {
      "package_path": "@healthmd/core-ts/candidate/codecs/*"
    },
    "expected": {
      "literal_exports_entry": false,
      "wildcard_match": false
    },
    "source_basis": "Original six literal exports plus sole new literal; no runtime loader execution yet"
  },
  {
    "case_id": "no-package-path-1",
    "group": "manifest",
    "input": {
      "package_path": "@healthmd/core-ts/serialization/exact-json-value"
    },
    "expected": {
      "literal_exports_entry": false,
      "wildcard_match": false
    },
    "source_basis": "Original six literal exports plus sole new literal; no runtime loader execution yet"
  },
  {
    "case_id": "no-package-path-2",
    "group": "manifest",
    "input": {
      "package_path": "@healthmd/core-ts/dist/core/serialization/exact-json-value.js"
    },
    "expected": {
      "literal_exports_entry": false,
      "wildcard_match": false
    },
    "source_basis": "Original six literal exports plus sole new literal; no runtime loader execution yet"
  },
  {
    "case_id": "no-package-path-3",
    "group": "manifest",
    "input": {
      "package_path": "@healthmd/core-ts/candidate/codecs/reader"
    },
    "expected": {
      "literal_exports_entry": false,
      "wildcard_match": false
    },
    "source_basis": "Original six literal exports plus sole new literal; no runtime loader execution yet"
  },
  {
    "case_id": "original-six-entries",
    "group": "manifest",
    "input": {
      "inspect": "package exports before and after"
    },
    "expected": {
      "old_entries": {
        ".": {
          "types": "./dist/core/index.d.ts",
          "import": "./dist/core/index.js"
        },
        "./host-interfaces": {
          "types": "./dist/core/host-interfaces/capabilities.d.ts",
          "import": "./dist/core/host-interfaces/capabilities.js"
        },
        "./candidate/catalog": {
          "types": "./dist/core/operations/catalog.d.ts",
          "import": "./dist/core/operations/catalog.js"
        },
        "./candidate/normalize": {
          "types": "./dist/core/operations/normalize.d.ts",
          "import": "./dist/core/operations/normalize.js"
        },
        "./candidate/query": {
          "types": "./dist/core/operations/query.d.ts",
          "import": "./dist/core/operations/query.js"
        },
        "./candidate/registry": {
          "types": "./dist/core/contracts/registry.d.ts",
          "import": "./dist/core/contracts/registry.js"
        }
      },
      "new_entries_only": [
        "./candidate/codecs"
      ],
      "dependency_lock_version_engines_files_scripts_unchanged": true
    },
    "source_basis": "Assigned Git package manifest"
  },
  {
    "case_id": "type-token-not-value",
    "group": "declarations",
    "input": {
      "attempt": "access readerToken.read or assign plain object to original opaque handle"
    },
    "expected": {
      "compile_rejected": true,
      "no_reader_method": true,
      "no_ast_access": true
    },
    "source_basis": "Nominal unique symbol brands and token empty handle"
  },
  {
    "case_id": "type-factory-composition",
    "group": "declarations",
    "input": {
      "attempt": "pass original factory.codec and original factory.readerToken to original facade serializer"
    },
    "expected": {
      "compile_accepted": true,
      "token_named_export_required": false
    },
    "source_basis": "Original unknown constructor parameters; samefactory runtime authentication remains mandatory"
  },
  {
    "case_id": "number-i64-min",
    "group": "number",
    "input": {
      "representation": "serde_value_default",
      "payload": "-9223372036854775808"
    },
    "expected": {
      "result": "success",
      "descriptor": {
        "class": "i64",
        "decimal": "-9223372036854775808"
      },
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Number98 class grammar and exact bits"
  },
  {
    "case_id": "number-u64-max",
    "group": "number",
    "input": {
      "representation": "serde_value_default",
      "payload": "18446744073709551615"
    },
    "expected": {
      "result": "success",
      "descriptor": {
        "class": "u64",
        "decimal": "18446744073709551615"
      },
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Number98 class grammar and exact bits"
  },
  {
    "case_id": "number-integer-one",
    "group": "number",
    "input": {
      "representation": "serde_value_default",
      "payload": "1"
    },
    "expected": {
      "result": "success",
      "descriptor": {
        "class": "u64",
        "decimal": "1"
      },
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Number98 class grammar and exact bits"
  },
  {
    "case_id": "number-decimal-one",
    "group": "number",
    "input": {
      "representation": "serde_value_default",
      "payload": "1.0"
    },
    "expected": {
      "result": "success",
      "descriptor": {
        "class": "f64",
        "bits": "3ff0000000000000"
      },
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Number98 class grammar and exact bits"
  },
  {
    "case_id": "number-negative-zero",
    "group": "number",
    "input": {
      "representation": "serde_value_default",
      "payload": "-0"
    },
    "expected": {
      "result": "success",
      "descriptor": {
        "class": "f64",
        "bits": "8000000000000000"
      },
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Number98 class grammar and exact bits"
  },
  {
    "case_id": "number-exponent-one",
    "group": "number",
    "input": {
      "representation": "serde_value_default",
      "payload": "1e0"
    },
    "expected": {
      "result": "success",
      "descriptor": {
        "class": "f64",
        "bits": "3ff0000000000000"
      },
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Number98 class grammar and exact bits"
  },
  {
    "case_id": "value-null",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "null",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "6e756c6c",
      "text": "null",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-bool",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "true",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "74727565",
      "text": "true",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-numeric-key-order",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "{\"2\":2,\"10\":1}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "7b223130223a312c2232223a327d",
      "text": "{\"10\":1,\"2\":2}",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-duplicate-decoded",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "{\"a\":1,\"\\u0061\":2}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "7b2261223a327d",
      "text": "{\"a\":2}",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-utf8-not-utf16",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "{\"\ud83d\ude00\":1,\"\ue000\":2}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "7b22ee8080223a322c22f09f9880223a317d",
      "text": "{\"\ue000\":2,\"\ud83d\ude00\":1}",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-array-order",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "[3,1,2]",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "5b332c312c325d",
      "text": "[3,1,2]",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-unknown-profile",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "{\"version\":\"001\",\"time\":\"0001\",\"unknown\":true}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "7b2274696d65223a2230303031222c22756e6b6e6f776e223a747275652c2276657273696f6e223a22303031227d",
      "text": "{\"time\":\"0001\",\"unknown\":true,\"version\":\"001\"}",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-raw-first",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"[1,2]\"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "5b312c325d",
      "text": "[1,2]",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-raw-later",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "{\"a\":1,\"$serde_json::private::RawValue\":\"true\"}",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "7b222473657264655f6a736f6e3a3a707269766174653a3a52617756616c7565223a2274727565222c2261223a317d",
      "text": "{\"$serde_json::private::RawValue\":\"true\",\"a\":1}",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-escape",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "\"\\u0000\\n\\\"\\\\/\"",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "225c75303030305c6e5c225c5c2f22",
      "text": "\"\\u0000\\n\\\"\\\\/\"",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-integer-u64",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "18446744073709551615",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "3138343436373434303733373039353531363135",
      "text": "18446744073709551615",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-f64-one",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "1.0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "312e30",
      "text": "1.0",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-f64-minus-zero",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "-0",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "2d302e30",
      "text": "-0.0",
      "original_and_facade_equal": true
    },
    "source_basis": "Accepted Value214/Canonical265 generic serde default/raw_value/UTF8 order literals"
  },
  {
    "case_id": "value-utf8hex",
    "group": "value_bytes",
    "input": {
      "representation": "utf8_hex",
      "payload": "225c753030653922",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "22c3a922",
      "text": "\"\u00e9\""
    },
    "source_basis": "Strict lowercase UTF8hex parse and compact unescaped Unicode"
  },
  {
    "case_id": "value-lf",
    "group": "value_bytes",
    "input": {
      "representation": "text",
      "payload": "{\"a\":1}",
      "policy": "serde_value_compact_lf"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "7b2261223a317d0a",
      "text": "{\"a\":1}\n",
      "LF_count": 1
    },
    "source_basis": "Accepted explicit22character LF policy"
  },
  {
    "case_id": "scalar-zero",
    "group": "scalar",
    "input": {
      "representation": "binary64",
      "payload": "8000000000000000"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "2d302e30",
      "text": "-0.0"
    },
    "source_basis": "Existing accepted scalar literal authority; no duplicate renderer"
  },
  {
    "case_id": "scalar-one",
    "group": "scalar",
    "input": {
      "representation": "binary64",
      "payload": "3ff0000000000000"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "312e30",
      "text": "1.0"
    },
    "source_basis": "Existing accepted scalar literal authority; no duplicate renderer"
  },
  {
    "case_id": "scalar-tenth",
    "group": "scalar",
    "input": {
      "representation": "binary64",
      "payload": "3fb999999999999a"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "302e31",
      "text": "0.1"
    },
    "source_basis": "Existing accepted scalar literal authority; no duplicate renderer"
  },
  {
    "case_id": "scalar-unsigned",
    "group": "scalar",
    "input": {
      "representation": "unsigned_integer",
      "payload": "18446744073709551615"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "3138343436373434303733373039353531363135",
      "text": "18446744073709551615"
    },
    "source_basis": "Existing accepted scalar literal authority; no duplicate renderer"
  },
  {
    "case_id": "scalar-signed",
    "group": "scalar",
    "input": {
      "representation": "signed_integer",
      "payload": "-9223372036854775808"
    },
    "expected": {
      "result": "success",
      "utf8_hex": "2d39323233333732303336383534373735383038",
      "text": "-9223372036854775808"
    },
    "source_basis": "Existing accepted scalar literal authority; no duplicate renderer"
  },
  {
    "case_id": "number-invalid-overflow",
    "group": "failure",
    "input": {
      "operation": "parse_number",
      "representation": "serde_value_default",
      "payload": "1e9999"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonNumberFailure",
        "code": "invalid_json_number"
      },
      "echo": false
    },
    "source_basis": "Original numeric grammar/finiteness admission"
  },
  {
    "case_id": "number-invalid-leading-zero",
    "group": "failure",
    "input": {
      "operation": "parse_number",
      "representation": "serde_value_default",
      "payload": "01"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonNumberFailure",
        "code": "invalid_json_number"
      },
      "echo": false
    },
    "source_basis": "Original numeric grammar/finiteness admission"
  },
  {
    "case_id": "number-invalid-trailing",
    "group": "failure",
    "input": {
      "operation": "parse_number",
      "representation": "serde_value_default",
      "payload": "1x"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonNumberFailure",
        "code": "invalid_json_number"
      },
      "echo": false
    },
    "source_basis": "Original numeric grammar/finiteness admission"
  },
  {
    "case_id": "value-invalid-utf8",
    "group": "failure",
    "input": {
      "operation": "parse_value",
      "representation": "utf8_hex",
      "payload": "22c08022"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "echo": false
    },
    "source_basis": "Original strict UTF8/surrogate/complete consumption policy"
  },
  {
    "case_id": "value-invalid-surrogate",
    "group": "failure",
    "input": {
      "operation": "parse_value",
      "representation": "text",
      "payload": "\"\\ud800\""
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "echo": false
    },
    "source_basis": "Original strict UTF8/surrogate/complete consumption policy"
  },
  {
    "case_id": "value-invalid-trailing",
    "group": "failure",
    "input": {
      "operation": "parse_value",
      "representation": "text",
      "payload": "nullx"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "echo": false
    },
    "source_basis": "Original strict UTF8/surrogate/complete consumption policy"
  },
  {
    "case_id": "construct-cross-token",
    "group": "ownership",
    "input": {
      "operation": "construct_serializer",
      "stimulus": "codecA+tokenB"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "reader_callbacks": 0
    },
    "source_basis": "Original capture authenticates same binding membership before properties"
  },
  {
    "case_id": "construct-foreign-codec",
    "group": "ownership",
    "input": {
      "operation": "construct_serializer",
      "stimulus": "plain object codec"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "reader_callbacks": 0
    },
    "source_basis": "Original capture authenticates same binding membership before properties"
  },
  {
    "case_id": "construct-foreign-token",
    "group": "ownership",
    "input": {
      "operation": "construct_serializer",
      "stimulus": "plain object token"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "reader_callbacks": 0
    },
    "source_basis": "Original capture authenticates same binding membership before properties"
  },
  {
    "case_id": "construct-proxy-codec",
    "group": "ownership",
    "input": {
      "operation": "construct_serializer",
      "stimulus": "throwing Proxy codec"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "reader_callbacks": 0
    },
    "source_basis": "Original capture authenticates same binding membership before properties"
  },
  {
    "case_id": "construct-revoked-token",
    "group": "ownership",
    "input": {
      "operation": "construct_serializer",
      "stimulus": "revoked Proxy token"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "reader_callbacks": 0
    },
    "source_basis": "Original capture authenticates same binding membership before properties"
  },
  {
    "case_id": "encode-cross-value",
    "group": "ownership",
    "input": {
      "operation": "encode",
      "stimulus": "own B handle passed to A serializer",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "published_output": false
    },
    "source_basis": "Original bound reader validates own WeakMap membership"
  },
  {
    "case_id": "encode-foreign-value",
    "group": "ownership",
    "input": {
      "operation": "encode",
      "stimulus": "plain object handle",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "published_output": false
    },
    "source_basis": "Original bound reader validates own WeakMap membership"
  },
  {
    "case_id": "encode-proxy-value",
    "group": "ownership",
    "input": {
      "operation": "encode",
      "stimulus": "throwing Proxy handle",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "published_output": false
    },
    "source_basis": "Original bound reader validates own WeakMap membership"
  },
  {
    "case_id": "encode-revoked-value",
    "group": "ownership",
    "input": {
      "operation": "encode",
      "stimulus": "revoked Proxy handle",
      "policy": "serde_value_compact"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0,
      "published_output": false
    },
    "source_basis": "Original bound reader validates own WeakMap membership"
  },
  {
    "case_id": "cross-number",
    "group": "ownership",
    "input": {
      "operation": "number_read",
      "stimulus": "own B number handle passed to A reader"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonNumberFailure",
        "code": "invalid_json_number"
      },
      "property_traps": 0
    },
    "source_basis": "Original per-number-factory private WeakMap"
  },
  {
    "case_id": "invalid-policy-proxy",
    "group": "ownership",
    "input": {
      "operation": "encode",
      "stimulus": "own A value + throwing Proxy policy"
    },
    "expected": {
      "result": "failure",
      "failure": {
        "_tag": "ExactJsonValueFailure",
        "code": "invalid_json_value"
      },
      "property_traps": 0,
      "coercions": 0
    },
    "source_basis": "Original primitive profile gate before owned graph read"
  },
  {
    "case_id": "fresh-output-carriers",
    "group": "ownership",
    "input": {
      "operation": "encode_twice",
      "payload": "null",
      "mutate_first_byte_to": 0
    },
    "expected": {
      "same_carrier": false,
      "second_utf8_hex": "6e756c6c",
      "source_graph_unchanged": true
    },
    "source_basis": "Original fresh Uint8Array result ownership"
  },
  {
    "case_id": "retained-corpus-scalar",
    "group": "retained_corpus",
    "input": {
      "fixture_path": "packages/healthmd-core-ts/tests/exact-json-numbers-vectors.ts",
      "replay": "actual original frozen stimuli through facade functions, no expected lookup in port",
      "count": null
    },
    "expected": {
      "fixture_bytes_unchanged": true,
      "original_frozen_expectations_pass": true,
      "no_expected_values_generated": true
    },
    "source_basis": "Accepted immutable corpus pinned in receipt; future execution required"
  },
  {
    "case_id": "retained-corpus-numbers",
    "group": "retained_corpus",
    "input": {
      "fixture_path": "packages/healthmd-core-ts/tests/exact-json-number-parser-vectors.ts",
      "replay": "actual original frozen stimuli through facade functions, no expected lookup in port",
      "count": 98
    },
    "expected": {
      "fixture_bytes_unchanged": true,
      "original_frozen_expectations_pass": true,
      "no_expected_values_generated": true
    },
    "source_basis": "Accepted immutable corpus pinned in receipt; future execution required"
  },
  {
    "case_id": "retained-corpus-values",
    "group": "retained_corpus",
    "input": {
      "fixture_path": "packages/healthmd-core-ts/tests/exact-json-value-vectors.ts",
      "replay": "actual original frozen stimuli through facade functions, no expected lookup in port",
      "count": 214
    },
    "expected": {
      "fixture_bytes_unchanged": true,
      "original_frozen_expectations_pass": true,
      "no_expected_values_generated": true
    },
    "source_basis": "Accepted immutable corpus pinned in receipt; future execution required"
  },
  {
    "case_id": "retained-corpus-serializer",
    "group": "retained_corpus",
    "input": {
      "fixture_path": "packages/healthmd-core-ts/tests/canonical-json-vectors.ts",
      "replay": "actual original frozen stimuli through facade functions, no expected lookup in port",
      "count": 265
    },
    "expected": {
      "fixture_bytes_unchanged": true,
      "original_frozen_expectations_pass": true,
      "no_expected_values_generated": true
    },
    "source_basis": "Accepted immutable corpus pinned in receipt; future execution required"
  },
  {
    "case_id": "pure-ownership-only",
    "group": "qualification",
    "input": {
      "operation": "factory/composition/encode in fake operation seam"
    },
    "expected": {
      "native_grants_proved": false,
      "source_authority_proved": false,
      "scope_authority_proved": false,
      "packed_consumer_admission": false
    },
    "source_basis": "Pure codec graph authenticity only; actual operation owns permissions/lifetime"
  }
] as const;

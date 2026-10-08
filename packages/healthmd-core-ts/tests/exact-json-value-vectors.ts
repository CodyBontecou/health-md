/* Source-only independent values Stage1: no parser/test implementation or oracle executed. */
import type * as Result from "effect/Result";
const valueBrand: unique symbol = Symbol("ownedJsonValue");
const codecBrand: unique symbol = Symbol("ownedJsonValueCodec");
const readerBrand: unique symbol = Symbol("ownedJsonValueReader");
export interface OwnedJsonValue { readonly [valueBrand]: true }
export interface OwnedJsonValueReaderToken { readonly [readerBrand]: true }
export interface ExactJsonValueFailure { readonly _tag: "ExactJsonValueFailure"; readonly code: "invalid_json_value" }
export type SourceNumericValue = { readonly class: "i64" | "u64"; readonly decimal: string } | { readonly class: "f64"; readonly bits: string };
export type ExactJsonValueNode =
  | { readonly kind: "null" }
  | { readonly kind: "boolean"; readonly value: boolean }
  | { readonly kind: "string"; readonly value: string }
  | { readonly kind: "number"; readonly value: SourceNumericValue }
  | { readonly kind: "array"; readonly items: readonly OwnedJsonValue[] }
  | { readonly kind: "object"; readonly entries: readonly (readonly [string, OwnedJsonValue])[] };
export interface OwnedJsonValueCodec {
  readonly [codecBrand]: true;
  readonly parse: (representation: unknown, payload: unknown) => Result.Result<OwnedJsonValue, ExactJsonValueFailure>;
}
export interface CapturedExactJsonValueReader {
  readonly read: (handle: unknown) => Result.Result<ExactJsonValueNode, ExactJsonValueFailure>;
}
export interface ExactJsonValueFactory { readonly codec: OwnedJsonValueCodec; readonly readerToken: OwnedJsonValueReaderToken }
export interface ExactJsonValueModule {
  readonly createExactJsonCodec: () => ExactJsonValueFactory;
  readonly captureExactJsonValueReader: (codec: unknown, readerToken: unknown) => Result.Result<CapturedExactJsonValueReader, ExactJsonValueFailure>;
}

export const exactJsonValueContract = {
  "status": "Stage1 source-only independentlyreviewable proposal, no implementation/oracle/check execution",
  "representation": [
    "text",
    "utf8_hex"
  ],
  "hex": "lowercase even-length [0-9a-f] only; primitive admission and2MiBcodeunitcap beforebyteallocation",
  "budgets": {
    "input_utf8_bytes": 1048576,
    "hex_code_units": 2097152,
    "container_nesting": 127,
    "parsed_value_nodes": 65536,
    "aggregate_decoded_string_utf8_bytes": 262144,
    "numeric_token_utf8_bytes": 1024,
    "total_json_scanned_utf8_bytes_all_raw_carrier_passes": 1048576
  },
  "accounting": "Allnodesincludingcontainers anddiscardedduplicatevalues; allparsedkeys andstringvalues includingduplicates/rawcarrierstrings countdecodedUTF8. EveryrawcarrierJSONreparse shares rootcounters, node/string/workbudgets, and activecontainerdepth; no percarrierreset. First completecallerUTF8validation/bytecount islinear bounded; recursiveJSONscannedbytecharge covers totalwork. Countfailedpartialnodes beforepublication; no handles returneduntilfullconsumption/allbudgets pass. ASTreader exposesonlyreachablefinalgraph, notdiscardednodes.",
  "raw_carrier_work_recipe": "Exactoutercarrier {\"$serde_json::private::RawValue\":\"null\"} is41ASCIIbytes, key30bytes and innernull4bytes. Prefix1048531whitespace yields outer1048572+inner4=1048576 aggregateJSONscanbytes, otherbudgetsfarbelowlimits. Prefix1048532 yields total1048577 withouter1048573<=inputcap; isolatesworkcap.",
  "numeric_binding": "Factorycreates accepted099505 numericparser once; captures originalparse/read functions andneveraccepts callernumericports. Everytoken delegates exactserde_value_default; numericOwnedhandle readthrough originalcapturedfactory and resultcopieddeepfrozen. No JSON.parse/wholetokenNumber/duplicatednumberparser/renderer.",
  "ownership": "Module-private WM authentically registers eachcodec/readerToken/handle; constantSymboltypingbrands are notruntimeauthority andopaquehandles/token frozenemptynullprototype. captureExactJsonValueReader checksauthenticcodec andsamefactoryreaderToken membership BEFOREproperties, returnsfixedoriginalboundread; neveraccepts callerreaderfunction. Foreigncodec/proxy/getter/reader/token/handle fixedfailurewithouttraps. Allarray/objectchildhandles samefactory; graphimmutable/private. Freshdeepfrozen shallow descriptors+freshentries/pairs/items/numericdescriptor; childhandles remainopaque. Reader functionoriginallycaptured, substitutions cannotreprovide.",
  "facade": "Internalpurefactory tuple suppliescodec+originalreaderToken toseparatelyclaimedserializer; externalconsumer facade exposescodec.parse only, neverreaderToken/AST/capture helper. capture helper isprivate module composition API, no package/rootexport admitted. Serializerconstructor capturesoriginalboundreader once; cantraverseanynode throughclosedshallowdescriptors withoutlaterparseredit. Noarbitraryvisitor/callerAST/service callbacks/toJSON/getters; noScope/grant/I/O/native/dataauthority.",
  "source_profile": "Actualdefault serde_json1.0.151 std/raw_value, nofloat_roundtrip/arbitrary_precision/preserve_order/unbounded_depth. Genericunknownkeys retainedanddecodedduplicatekeys lastwins, EXCEPTfirstdecodedRawValuecarrier key followsretainedsource specialreparse; samekeylater ordinaryMap. ArbitraryNumbercarrier remainsordinaryMap. Typed contractdenyunknown/duplicate/version/requiredfields remainlaterowner.",
  "order": "Arrays sourceorder; objectdecodedunique keysRustUTF8/scalar lexicographic BTreeMaporder, not JSnumericenumeration/UTF16sort; no Unicode normalization. Linear lexicalscan distinguishedfrom bounded keyordering. No claim allsorting islinear.",
  "strings": "Strict UTF16 surrogatepairs for text preadmission andstrict UTF8shortestscalarsequence forhex; controlsU0000..001F mustescaped; acceptedJSONescapes onlyquote/backslash/slash/b/f/n/r/t/u4hex; escapedsurrogates mustpaired. JSONwhitespace exactlySP/LF/CR/TAB; completeconsumption.",
  "failure": {
    "_tag": "ExactJsonValueFailure",
    "code": "invalid_json_value"
  },
  "qualification": "Privatecaps stricterthanfullunboundedRustsource; corpus doesnotqualify serializercompactbytes/typedcontracts/public/native/engine/package/export/cohort/consumerparity. Original16compactproposal minima preserved but compactbytes future serializer evidence, parse tree expectations separate.",
  "ownership_scenario_setup": {
    "fresh_per_case": "Createfreshfactories A/B with authcodecA/B readerTokensA/B. Eachprimitive parse usesliteral textseed below; save originalcapturedreadA/B throughmodulecapture once. AllharnessrootA/B andchildA/B references meanauthentichandles producedbythesefactories; childB isfirstelementofauthenticarrayentrya from rootB. No expected-value lookup createsinputs.",
    "text_seed": "{\"a\":[1,-0],\"b\":{\"x\":\"\u00e9\"}}",
    "caller_Proxy": "throwinghandlers get/set/has/ownKeys/getPrototypeOf/getOwnPropertyDescriptor/defineProperty/isExtensible countcallertraps; catchmustnotexposecause",
    "forgery": "callerplainobject matchingvisiblefields orlocalSymbolbrand neverWeakMapauthentic; accessorforgegetterparse throws iftouched",
    "closure": "Real unrelatedEffect Scope finalizer acknowledgesclosure and setsoperationLivefalse; closedoperationauthority explicitlyharness-owned, codec lacksanyScope/grant/source methods andcannotreactivateoperation. No nativegrantproof."
  }
} as const;

export const retainedValuePacketProposals = [
  {
    "case_id": "value-decoded-duplicate",
    "input": "{\"a\":1,\"\\u0061\":2}",
    "expected": {
      "compact": "{\"a\":2}"
    },
    "source_basis": "value/de.rs decoded Map insert last value",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-nested-order",
    "input": "{\"z\":{\"b\":1,\"a\":2},\"a\":[2,1]}",
    "expected": {
      "compact": "{\"a\":[2,1],\"z\":{\"a\":2,\"b\":1}}"
    },
    "source_basis": "BTreeMap recursively sorted, arrays unchanged",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-integer-key-order",
    "input": "{\"2\":0,\"10\":0,\"1\":0}",
    "expected": {
      "compact": "{\"1\":0,\"10\":0,\"2\":0}"
    },
    "source_basis": "Rust string order, not JS object enumeration",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-supplementary-order",
    "input": "{\"\ud800\udc00\":1,\"\ue000\":2}",
    "expected": {
      "compact": "{\"\ue000\":2,\"\ud800\udc00\":1}"
    },
    "source_basis": "UTF8/scalar order differs JS UTF16 sort",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-surrogate-pair",
    "input": "\"\\ud83d\\ude00\"",
    "expected": {
      "compact": "\"\ud83d\ude00\""
    },
    "source_basis": "read.rs validated surrogate pairing",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-lone-high",
    "input": "\"\\ud800\"",
    "expected": {
      "error": "invalid_json_value"
    },
    "source_basis": "UTF8 String validation",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-lone-low",
    "input": "\"\\udc00\"",
    "expected": {
      "error": "invalid_json_value"
    },
    "source_basis": "UTF8 String validation",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-control-escape",
    "input": "\"\\u0000\\b\\t\\n\\f\\r\"",
    "expected": {
      "compact": "\"\\u0000\\b\\t\\n\\f\\r\""
    },
    "source_basis": "ser.rs escape table",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-slash-nonescape",
    "input": "\"\\/\"",
    "expected": {
      "compact": "\"/\""
    },
    "source_basis": "slash decoder accepted serializer unescaped",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-whitespace",
    "input": " \n [null,true,false] \t",
    "expected": {
      "compact": "[null,true,false]"
    },
    "source_basis": "JSON whitespace/full consumption",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-trailing",
    "input": "{}{}",
    "expected": {
      "error": "invalid_json_value"
    },
    "source_basis": "full input consumption",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-comments",
    "input": "/*x*/{}",
    "expected": {
      "error": "invalid_json_value"
    },
    "source_basis": "no comments",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-unknown-generic",
    "input": "{\"unrecognized\":1}",
    "expected": {
      "compact": "{\"unrecognized\":1}"
    },
    "source_basis": "generic Value keeps keys; not typed deny_unknown_fields",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-invalid-utf8",
    "input": {
      "representation": "utf8_hex",
      "payload": "22c08022"
    },
    "expected": {
      "error": "invalid_json_value"
    },
    "source_basis": "overlong UTF8 rejected before decode",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-closed-bounds",
    "input": {
      "harness": "1MiB+1 input, depth128, nodes65537, string262145, numeric token1025 independently"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "private proposed budgets; boundary+1 cases independently frozen",
    "status": "proposed_independent_literal_review_required"
  },
  {
    "case_id": "value-nonprimitive",
    "input": {
      "harness": "proxy/accessor payload"
    },
    "expected": {
      "error": "invalid_json_value",
      "traps": 0
    },
    "source_basis": "primitive before inspection",
    "status": "proposed_independent_literal_review_required"
  }
] as const;

export const exactJsonValueVectors = [
  {
    "case_id": "value-decoded-duplicate",
    "input": {
      "representation": "text",
      "payload": "{\"a\":1,\"\\u0061\":2}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "a",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "2"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-nested-order",
    "input": {
      "representation": "text",
      "payload": "{\"z\":{\"b\":1,\"a\":2},\"a\":[2,1]}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "a",
            {
              "kind": "array",
              "items": [
                {
                  "kind": "number",
                  "value": {
                    "class": "u64",
                    "decimal": "2"
                  }
                },
                {
                  "kind": "number",
                  "value": {
                    "class": "u64",
                    "decimal": "1"
                  }
                }
              ]
            }
          ],
          [
            "z",
            {
              "kind": "object",
              "entries": [
                [
                  "a",
                  {
                    "kind": "number",
                    "value": {
                      "class": "u64",
                      "decimal": "2"
                    }
                  }
                ],
                [
                  "b",
                  {
                    "kind": "number",
                    "value": {
                      "class": "u64",
                      "decimal": "1"
                    }
                  }
                ]
              ]
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-integer-key-order",
    "input": {
      "representation": "text",
      "payload": "{\"2\":0,\"10\":0,\"1\":0}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "1",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "0"
              }
            }
          ],
          [
            "10",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "0"
              }
            }
          ],
          [
            "2",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "0"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-supplementary-order",
    "input": {
      "representation": "text",
      "payload": "{\"\ud800\udc00\":1,\"\ue000\":2}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "\ue000",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "2"
              }
            }
          ],
          [
            "\ud800\udc00",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "1"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-surrogate-pair",
    "input": {
      "representation": "text",
      "payload": "\"\\ud83d\\ude00\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\ud83d\ude00"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-lone-high",
    "input": {
      "representation": "text",
      "payload": "\"\\ud800\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-lone-low",
    "input": {
      "representation": "text",
      "payload": "\"\\udc00\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-control-escape",
    "input": {
      "representation": "text",
      "payload": "\"\\u0000\\b\\t\\n\\f\\r\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\u0000\b\t\n\f\r"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-slash-nonescape",
    "input": {
      "representation": "text",
      "payload": "\"\\/\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "/"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-whitespace",
    "input": {
      "representation": "text",
      "payload": " \n [null,true,false] \t"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "null"
          },
          {
            "kind": "boolean",
            "value": true
          },
          {
            "kind": "boolean",
            "value": false
          }
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-trailing",
    "input": {
      "representation": "text",
      "payload": "{}{}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-comments",
    "input": {
      "representation": "text",
      "payload": "/*x*/{}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-unknown-generic",
    "input": {
      "representation": "text",
      "payload": "{\"unrecognized\":1}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "unrecognized",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "1"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-invalid-utf8",
    "input": {
      "representation": "utf8_hex",
      "payload": "22c08022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-null",
    "input": {
      "representation": "text",
      "payload": "null"
    },
    "expected": {
      "tree": {
        "kind": "null"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-true",
    "input": {
      "representation": "text",
      "payload": "true"
    },
    "expected": {
      "tree": {
        "kind": "boolean",
        "value": true
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-false",
    "input": {
      "representation": "text",
      "payload": "false"
    },
    "expected": {
      "tree": {
        "kind": "boolean",
        "value": false
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-emptystring",
    "input": {
      "representation": "text",
      "payload": "\"\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": ""
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-emptyarray",
    "input": {
      "representation": "text",
      "payload": "[]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": []
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-emptyobject",
    "input": {
      "representation": "text",
      "payload": "{}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": []
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-mixed",
    "input": {
      "representation": "text",
      "payload": "[{},[],\"x\",false,null]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "object",
            "entries": []
          },
          {
            "kind": "array",
            "items": []
          },
          {
            "kind": "string",
            "value": "x"
          },
          {
            "kind": "boolean",
            "value": false
          },
          {
            "kind": "null"
          }
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-reject-empty",
    "input": {
      "representation": "text",
      "payload": ""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-ws-only",
    "input": {
      "representation": "text",
      "payload": " \t\r\n"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-undefined",
    "input": {
      "representation": "text",
      "payload": "undefined"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-nan",
    "input": {
      "representation": "text",
      "payload": "NaN"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-inf",
    "input": {
      "representation": "text",
      "payload": "Infinity"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-plus",
    "input": {
      "representation": "text",
      "payload": "+1"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-leadingzero",
    "input": {
      "representation": "text",
      "payload": "01"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-negative-leadingzero",
    "input": {
      "representation": "text",
      "payload": "-01"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-missingfraction",
    "input": {
      "representation": "text",
      "payload": "1."
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-missingexp",
    "input": {
      "representation": "text",
      "payload": "1e"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-overflow",
    "input": {
      "representation": "text",
      "payload": "1e9999"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-boolsuffix",
    "input": {
      "representation": "text",
      "payload": "truex"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-nullsuffix",
    "input": {
      "representation": "text",
      "payload": "null0"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-twovalues",
    "input": {
      "representation": "text",
      "payload": "true false"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-array-trailing-comma",
    "input": {
      "representation": "text",
      "payload": "[1,]"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-object-trailing-comma",
    "input": {
      "representation": "text",
      "payload": "{\"a\":1,}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-missing-comma",
    "input": {
      "representation": "text",
      "payload": "[1 2]"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-double-comma",
    "input": {
      "representation": "text",
      "payload": "[1,,2]"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-missing-colon",
    "input": {
      "representation": "text",
      "payload": "{\"a\" 1}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-unquoted-key",
    "input": {
      "representation": "text",
      "payload": "{a:1}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-number-key",
    "input": {
      "representation": "text",
      "payload": "{1:1}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-single-quote",
    "input": {
      "representation": "text",
      "payload": "'a'"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-unclosed-array",
    "input": {
      "representation": "text",
      "payload": "["
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-unclosed-object",
    "input": {
      "representation": "text",
      "payload": "{"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-unclosed-string",
    "input": {
      "representation": "text",
      "payload": "\"x"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-incomplete-backslash",
    "input": {
      "representation": "text",
      "payload": "\"x\\"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-invalidescape",
    "input": {
      "representation": "text",
      "payload": "\"\\x20\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-incomplete-unicode",
    "input": {
      "representation": "text",
      "payload": "\"\\u123\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-invalid-unicode-hex",
    "input": {
      "representation": "text",
      "payload": "\"\\u00xz\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-high-followed-bmp",
    "input": {
      "representation": "text",
      "payload": "\"\\ud800\\u0061\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-high-followed-high",
    "input": {
      "representation": "text",
      "payload": "\"\\ud800\\ud800\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-high-followed-escape",
    "input": {
      "representation": "text",
      "payload": "\"\\ud800\\n\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-low-then-high",
    "input": {
      "representation": "text",
      "payload": "\"\\udc00\\ud800\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-NBSP-ws",
    "input": {
      "representation": "text",
      "payload": "\u00a0null"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-BOM",
    "input": {
      "representation": "text",
      "payload": "\ufeffnull"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-VT-ws",
    "input": {
      "representation": "text",
      "payload": "\u000bnull"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-FF-ws",
    "input": {
      "representation": "text",
      "payload": "\fnull"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-rawcontrol",
    "input": {
      "representation": "text",
      "payload": "\"\u0000\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-rawnewline",
    "input": {
      "representation": "text",
      "payload": "\"\n\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-rawtab",
    "input": {
      "representation": "text",
      "payload": "\"\t\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-raw-high-surrogate",
    "input": {
      "representation": "text",
      "payload": "\"\ud800\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-raw-low-surrogate",
    "input": {
      "representation": "text",
      "payload": "\"\udc00\""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-string-quotes",
    "input": {
      "representation": "text",
      "payload": "\"\\\"\\\\\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\"\\"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-string-unicodehexcase",
    "input": {
      "representation": "text",
      "payload": "\"\\u00e9\\u00E9\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\u00e9\u00e9"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-string-unicode-limits",
    "input": {
      "representation": "text",
      "payload": "\"\\ud800\\udc00\\udbff\\udfff\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\ud800\udc00\udbff\udfff"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-string-raw-utf8",
    "input": {
      "representation": "text",
      "payload": "\"\u00e9\ud83d\ude00\u2028\u2029\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\u00e9\ud83d\ude00\u2028\u2029"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-string-escaped-control-max",
    "input": {
      "representation": "text",
      "payload": "\"\\u001f\""
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\u001f"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-string-escaped-key",
    "input": {
      "representation": "text",
      "payload": "{\"\\u0062\":1,\"a\":2}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "a",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "2"
              }
            }
          ],
          [
            "b",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "1"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-duplicate-nested",
    "input": {
      "representation": "text",
      "payload": "{\"a\":{\"x\":1},\"a\":[2]}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "a",
            {
              "kind": "array",
              "items": [
                {
                  "kind": "number",
                  "value": {
                    "class": "u64",
                    "decimal": "2"
                  }
                }
              ]
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-key-prototype-names",
    "input": {
      "representation": "text",
      "payload": "{\"__proto__\":1,\"constructor\":2,\"toJSON\":3}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "__proto__",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "1"
              }
            }
          ],
          [
            "constructor",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "2"
              }
            }
          ],
          [
            "toJSON",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "3"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-key-empty-and-controls",
    "input": {
      "representation": "text",
      "payload": "{\"z\":0,\"\\u0000\":1,\"\":2}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "2"
              }
            }
          ],
          [
            "\u0000",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "1"
              }
            }
          ],
          [
            "z",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "0"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-no-unicode-normalization",
    "input": {
      "representation": "text",
      "payload": "{\"\u00e9\":1,\"e\\u0301\":2}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "e\u0301",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "2"
              }
            }
          ],
          [
            "\u00e9",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "1"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-tagged-i128-not-reinterpreted",
    "input": {
      "representation": "text",
      "payload": "{\"type\":\"signed_integer\",\"decimal\":\"170141183460469231731687303715884105727\"}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "decimal",
            {
              "kind": "string",
              "value": "170141183460469231731687303715884105727"
            }
          ],
          [
            "type",
            {
              "kind": "string",
              "value": "signed_integer"
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-tagged-u128-not-reinterpreted",
    "input": {
      "representation": "text",
      "payload": "{\"type\":\"unsigned_integer\",\"decimal\":\"340282366920938463463374607431768211455\"}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "decimal",
            {
              "kind": "string",
              "value": "340282366920938463463374607431768211455"
            }
          ],
          [
            "type",
            {
              "kind": "string",
              "value": "unsigned_integer"
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-numeric-number-u64-one",
    "input": {
      "representation": "text",
      "payload": "[1]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "1"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; de.rs parse_number positive integer"
  },
  {
    "case_id": "value-numeric-number-i64-minus-one",
    "input": {
      "representation": "text",
      "payload": "[-1]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "i64",
              "decimal": "-1"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; de.rs negative integer"
  },
  {
    "case_id": "value-numeric-number-minus-zero",
    "input": {
      "representation": "text",
      "payload": "[-0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; de.rs explicitly promotes -0 to F64"
  },
  {
    "case_id": "value-numeric-number-decimal-one",
    "input": {
      "representation": "text",
      "payload": "[1.0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; parse_decimal"
  },
  {
    "case_id": "value-numeric-number-exponent-one",
    "input": {
      "representation": "text",
      "payload": "[1e0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; parse_exponent"
  },
  {
    "case_id": "value-numeric-number-i64-min",
    "input": {
      "representation": "text",
      "payload": "[-9223372036854775808]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "i64",
              "decimal": "-9223372036854775808"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; negative wrapping boundary"
  },
  {
    "case_id": "value-numeric-number-u64-max",
    "input": {
      "representation": "text",
      "payload": "[18446744073709551615]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "18446744073709551615"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; u64 max"
  },
  {
    "case_id": "value-numeric-number-unsafe-integer",
    "input": {
      "representation": "text",
      "payload": "[9007199254740993]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "9007199254740993"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; no Number/JSON.parse rounding"
  },
  {
    "case_id": "value-numeric-number-u64-overflow",
    "input": {
      "representation": "text",
      "payload": "[18446744073709551616]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "43f0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; default parse_long_integer, exactly2^64"
  },
  {
    "case_id": "value-numeric-number-negative-underflow",
    "input": {
      "representation": "text",
      "payload": "[-1e-999]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; negative exponent underflow preserves sign"
  },
  {
    "case_id": "value-numeric-number-zero-huge-exponent",
    "input": {
      "representation": "text",
      "payload": "[0e999999999999999999999]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; parse_exponent_overflow zero_significand"
  },
  {
    "case_id": "value-numeric-decimal-tenth",
    "input": {
      "representation": "text",
      "payload": "[0.1]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3fb999999999999a"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-decimal-three-tenths",
    "input": {
      "representation": "text",
      "payload": "[0.3]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3fd3333333333333"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-long-fraction",
    "input": {
      "representation": "text",
      "payload": "[0.123456789012345678901234567890]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3fbf9add3746f65f"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-long-positive",
    "input": {
      "representation": "text",
      "payload": "[1.23456789012345678901234567890]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff3c0ca428c59fb"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-u64-overflow-dropped",
    "input": {
      "representation": "text",
      "payload": "[18446744073709551619]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "43f0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-i64-negative-underflow",
    "input": {
      "representation": "text",
      "payload": "[-9223372036854775809]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "c3e0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-u64-max-decimal",
    "input": {
      "representation": "text",
      "payload": "[18446744073709551615.0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "43f0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-integer-overflow-then-decimal",
    "input": {
      "representation": "text",
      "payload": "[184467440737095516160.5]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "4424000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-unsafe-integer-decimal",
    "input": {
      "representation": "text",
      "payload": "[9007199254740993.0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "4340000000000001"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-max-finite-decimal",
    "input": {
      "representation": "text",
      "payload": "[1.7976931348623157e308]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "7fefffffffffffff"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-min-normal-decimal",
    "input": {
      "representation": "text",
      "payload": "[2.2250738585072014e-308]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0010000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-min-subnormal",
    "input": {
      "representation": "text",
      "payload": "[5e-324]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000001"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-under-half-subnormal",
    "input": {
      "representation": "text",
      "payload": "[2e-324]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-above-half-subnormal",
    "input": {
      "representation": "text",
      "payload": "[3e-324]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000001"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-negative-min-subnormal",
    "input": {
      "representation": "text",
      "payload": "[-5e-324]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000001"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-deep-underflow",
    "input": {
      "representation": "text",
      "payload": "[1e-999]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-negative-deep-underflow",
    "input": {
      "representation": "text",
      "payload": "[-1e-999]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-power-positive",
    "input": {
      "representation": "text",
      "payload": "[1e23]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "44b52d02c7e14af6"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-power-negative",
    "input": {
      "representation": "text",
      "payload": "[1e-23]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3b282db34012b252"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-large-cast-tie-even-down",
    "input": {
      "representation": "text",
      "payload": "[9007199254740993e0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "4340000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-large-cast-tie-even-up",
    "input": {
      "representation": "text",
      "payload": "[9007199254740995e0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "4340000000000002"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-long-decimal-dropped-digits",
    "input": {
      "representation": "text",
      "payload": "[0.1000000000000000055511151231257827021181583404541015625]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3fb999999999999a"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "value-numeric-integer-zero",
    "input": {
      "representation": "text",
      "payload": "[0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "0"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "value-numeric-i64-max-as-u64",
    "input": {
      "representation": "text",
      "payload": "[9223372036854775807]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "9223372036854775807"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "value-numeric-positive-over-i64",
    "input": {
      "representation": "text",
      "payload": "[9223372036854775808]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "9223372036854775808"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "value-numeric-negative-i64-neighbor",
    "input": {
      "representation": "text",
      "payload": "[-9223372036854775807]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "i64",
              "decimal": "-9223372036854775807"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "value-numeric-negative-safe-integer",
    "input": {
      "representation": "text",
      "payload": "[-9007199254740993]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "i64",
              "decimal": "-9007199254740993"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "value-numeric-negative-decimal-zero",
    "input": {
      "representation": "text",
      "payload": "[-0.0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-negative-exponent-zero",
    "input": {
      "representation": "text",
      "payload": "[-0E+0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-positive-exponent-plus",
    "input": {
      "representation": "text",
      "payload": "[1e+00]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-positive-uppercase-exponent",
    "input": {
      "representation": "text",
      "payload": "[1E0]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-zero-positive-i32-overflow",
    "input": {
      "representation": "text",
      "payload": "[0e2147483648]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-negative-zero-positive-i32-overflow",
    "input": {
      "representation": "text",
      "payload": "[-0e2147483648]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-zero-negative-i32-overflow",
    "input": {
      "representation": "text",
      "payload": "[0e-2147483648]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-negative-positive-i32-underflow",
    "input": {
      "representation": "text",
      "payload": "[-1e-2147483648]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-negativezero-underflow",
    "input": {
      "representation": "text",
      "payload": "[-0e-99999]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-fraction-trailing-zero",
    "input": {
      "representation": "text",
      "payload": "[1.00000000000000000000]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-truncated-fraction-not-integer",
    "input": {
      "representation": "text",
      "payload": "[1.00000000000000000001]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-bound-exponent-zeros",
    "input": {
      "representation": "text",
      "payload": "[1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "3ff0000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-numeric-bound-zero-fraction",
    "input": {
      "representation": "text",
      "payload": "[0.00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000]"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "0000000000000000"
            }
          }
        ]
      }
    },
    "source_basis": "Accepted independent numeric22880c literal; captured original parser+read; Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "value-utf8-ascii",
    "input": {
      "representation": "utf8_hex",
      "payload": "226122"
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "a"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-utf8-two",
    "input": {
      "representation": "utf8_hex",
      "payload": "22c3a922"
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\u00e9"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-utf8-three",
    "input": {
      "representation": "utf8_hex",
      "payload": "22ee808022"
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\ue000"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-utf8-four",
    "input": {
      "representation": "utf8_hex",
      "payload": "22f09f988022"
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\ud83d\ude00"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-utf8-max",
    "input": {
      "representation": "utf8_hex",
      "payload": "22f48fbfbf22"
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\udbff\udfff"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-utf8-null",
    "input": {
      "representation": "utf8_hex",
      "payload": "6e756c6c"
    },
    "expected": {
      "tree": {
        "kind": "null"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-reject-hex-overlong3",
    "input": {
      "representation": "utf8_hex",
      "payload": "22e0808022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-overlong4",
    "input": {
      "representation": "utf8_hex",
      "payload": "22f080808022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-surrogate",
    "input": {
      "representation": "utf8_hex",
      "payload": "22eda08022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-aboveunicode",
    "input": {
      "representation": "utf8_hex",
      "payload": "22f490808022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-leadf5",
    "input": {
      "representation": "utf8_hex",
      "payload": "22f580808022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-continuation",
    "input": {
      "representation": "utf8_hex",
      "payload": "228022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-truncated2",
    "input": {
      "representation": "utf8_hex",
      "payload": "22c222"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-truncated4",
    "input": {
      "representation": "utf8_hex",
      "payload": "22f09f9822"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-nonhex",
    "input": {
      "representation": "utf8_hex",
      "payload": "22gg22"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-oddhex",
    "input": {
      "representation": "utf8_hex",
      "payload": "226"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-uppercase",
    "input": {
      "representation": "utf8_hex",
      "payload": "22C3A922"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-emptyhex",
    "input": {
      "representation": "utf8_hex",
      "payload": ""
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-BOMhex",
    "input": {
      "representation": "utf8_hex",
      "payload": "efbbbf6e756c6c"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-reject-hex-hexrawcontrol",
    "input": {
      "representation": "utf8_hex",
      "payload": "220022"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary JSON grammar/strictUTF8/string/fullconsumption"
  },
  {
    "case_id": "value-raw-first-number",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"1\"}"
    },
    "expected": {
      "tree": {
        "kind": "number",
        "value": {
          "class": "u64",
          "decimal": "1"
        }
      }
    },
    "source_basis": "value/de125-145 +KeyClassifier1363-1379; raw.rs476-509; actualdefault raw_value enabled"
  },
  {
    "case_id": "value-raw-first-nested",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"{\\\"z\\\":1,\\\"a\\\":[-0,1.0]}\"}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "a",
            {
              "kind": "array",
              "items": [
                {
                  "kind": "number",
                  "value": {
                    "class": "f64",
                    "bits": "8000000000000000"
                  }
                },
                {
                  "kind": "number",
                  "value": {
                    "class": "f64",
                    "bits": "3ff0000000000000"
                  }
                }
              ]
            }
          ],
          [
            "z",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "1"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-raw-first-escaped-key",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawVal\\u0075e\":\"true\"}"
    },
    "expected": {
      "tree": {
        "kind": "boolean",
        "value": true
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-raw-first-string",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"\\\"x\\\"\"}"
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "x"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-raw-first-whitespace",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\" \\n null \\t\"}"
    },
    "expected": {
      "tree": {
        "kind": "null"
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-raw-reject-nonstring",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":1}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary raw_value sourcecarrier exception/fullend_map; nottyped unknownfieldpolicy"
  },
  {
    "case_id": "value-raw-reject-invalid",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"{}{}\"}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary raw_value sourcecarrier exception/fullend_map; nottyped unknownfieldpolicy"
  },
  {
    "case_id": "value-raw-reject-inneroverflow",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"1e9999\"}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary raw_value sourcecarrier exception/fullend_map; nottyped unknownfieldpolicy"
  },
  {
    "case_id": "value-raw-reject-additional-member",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"1\",\"a\":2}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary raw_value sourcecarrier exception/fullend_map; nottyped unknownfieldpolicy"
  },
  {
    "case_id": "value-raw-reject-duplicate-carrier",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"1\",\"$serde_json::private::RawValue\":\"2\"}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary raw_value sourcecarrier exception/fullend_map; nottyped unknownfieldpolicy"
  },
  {
    "case_id": "value-raw-reject-inner-lone-surrogate",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"\\\"\\\\ud800\\\"\"}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Primary raw_value sourcecarrier exception/fullend_map; nottyped unknownfieldpolicy"
  },
  {
    "case_id": "value-raw-later-ordinary",
    "input": {
      "representation": "text",
      "payload": "{\"a\":0,\"$serde_json::private::RawValue\":\"1\"}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "$serde_json::private::RawValue",
            {
              "kind": "string",
              "value": "1"
            }
          ],
          [
            "a",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "0"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-raw-later-nonstring",
    "input": {
      "representation": "text",
      "payload": "{\"a\":0,\"$serde_json::private::RawValue\":2}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "$serde_json::private::RawValue",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "2"
              }
            }
          ],
          [
            "a",
            {
              "kind": "number",
              "value": {
                "class": "u64",
                "decimal": "0"
              }
            }
          ]
        ]
      }
    },
    "source_basis": "Primary genericValue grammar/decoded keys/arrays/numericclasses"
  },
  {
    "case_id": "value-arbitrary-number-carrier-absent",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::Number\":\"1e9999\"}"
    },
    "expected": {
      "tree": {
        "kind": "object",
        "entries": [
          [
            "$serde_json::private::Number",
            {
              "kind": "string",
              "value": "1e9999"
            }
          ]
        ]
      }
    },
    "source_basis": "arbitrary_precision absentactualdefaultmetadata; genericunknown Map"
  },
  {
    "case_id": "value-bound-input-at",
    "input": {
      "harness": "text: null + ASCII-space repeated1048572"
    },
    "expected": {
      "root_kind": "null",
      "input_utf8_bytes": 1048576,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-input-over",
    "input": {
      "harness": "text: null + ASCII-space repeated1048573"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-input-multibyte-at",
    "input": {
      "harness": "text: quoted\u00e9 + ASCII-space repeated1048572"
    },
    "expected": {
      "tree": {
        "kind": "string",
        "value": "\u00e9"
      },
      "input_utf8_bytes": 1048576,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-input-multibyte-over",
    "input": {
      "harness": "text: quoted\u00e9 + ASCII-space repeated1048573"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-hex-at",
    "input": {
      "harness": "utf8_hex: 6e756c6c + 20 repeated1048572"
    },
    "expected": {
      "root_kind": "null",
      "input_utf8_bytes": 1048576,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-hex-over",
    "input": {
      "harness": "utf8_hex: 6e756c6c + 20 repeated1048573"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-depth-at",
    "input": {
      "harness": "text: [ repeated127 + null + ] repeated127"
    },
    "expected": {
      "root_kind": "array",
      "container_depth": 127,
      "parsed_nodes": 128,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-depth-over",
    "input": {
      "harness": "text: [ repeated128 + null + ] repeated128"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-nodes-at",
    "input": {
      "harness": "text: array of65535 comma-separated nulls"
    },
    "expected": {
      "root_kind": "array",
      "array_length": 65535,
      "parsed_nodes": 65536,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-nodes-over",
    "input": {
      "harness": "text: array of65536 comma-separated nulls"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-string-at",
    "input": {
      "harness": "text: quoted ASCIIa repeated262144"
    },
    "expected": {
      "root_kind": "string",
      "decoded_utf8_bytes": 262144,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-string-over",
    "input": {
      "harness": "text: quoted ASCIIa repeated262145"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-string-multibyte-at",
    "input": {
      "harness": "text: quoted\u00e9 repeated131072"
    },
    "expected": {
      "root_kind": "string",
      "decoded_utf8_bytes": 262144,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-string-multibyte-over",
    "input": {
      "harness": "text: quoted\u00e9 repeated131073"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-aggregate-strings-at",
    "input": {
      "harness": "text: object with ASCIIa repeated131072 key and ASCIIb repeated131072 stringvalue"
    },
    "expected": {
      "root_kind": "object",
      "entry_count": 1,
      "parsed_nodes": 2,
      "decoded_utf8_bytes": 262144,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-aggregate-strings-over",
    "input": {
      "harness": "text: sameobject but valueASCIIb repeated131073"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-discarded-key-strings-at",
    "input": {
      "harness": "text: object with duplicate keya and131071-byteASCIIb then131071-byteASCIIc stringvalues"
    },
    "expected": {
      "root_kind": "object",
      "entry_count": 1,
      "parsed_nodes": 3,
      "decoded_utf8_bytes": 262144,
      "last_value_length": 131071,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-discarded-key-strings-over",
    "input": {
      "harness": "text: sameduplicateobject but lastASCIIc stringvalue131072bytes"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-discarded-values-node-over",
    "input": {
      "harness": "text: object of65536 duplicate keya:null members"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-numeric-token-at",
    "input": {
      "harness": "text: 0e- + ASCII0 repeated1020 + 1 (token1024)"
    },
    "expected": {
      "tree": {
        "kind": "number",
        "value": {
          "class": "f64",
          "bits": "0000000000000000"
        }
      },
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-numeric-token-over",
    "input": {
      "harness": "text: 0e- + ASCII0 repeated1021 + 1 (token1025)"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-raw-work-at",
    "input": {
      "harness": "text: ASCIIspace repeated1048531 then literal{\"$serde_json::private::RawValue\":\"null\"}"
    },
    "expected": {
      "tree": {
        "kind": "null"
      },
      "total_json_scanned_utf8_bytes": 1048576,
      "outer_input_utf8_bytes": 1048572,
      "aggregate_decoded_string_utf8_bytes": 34,
      "parsed_nodes": 3,
      "published": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-raw-work-over",
    "input": {
      "harness": "text: ASCIIspace repeated1048532 then literal{\"$serde_json::private::RawValue\":\"null\"}"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false,
      "outer_input_utf8_bytes": 1048573,
      "total_json_scanned_utf8_bytes": 1048577
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-raw-depth-over",
    "input": {
      "harness": "text: firstrawcarrier stringvalue encoding127 nested arrays aroundnull; outercarrierobject depth1 makes sharedactivecontainerdepth128"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-raw-node-over",
    "input": {
      "harness": "text: firstrawcarrier stringvalue encodingarray65534zeros; outercarrierobject+string2nodes plus innerarray+65534zeros65535nodes =65537total; innerstring131069ASCIIbytes belowstringcap"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-raw-string-over",
    "input": {
      "harness": "text: firstrawcarrier stringvalue encodingquotedASCIIa131072; carrierdecodedstringbytes131074 + innerdecodedstringbytes131072 total262146"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-preallocation-giant-text",
    "input": {
      "harness": "text primitive ASCIIspace repeated1048577"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-preallocation-giant-hex",
    "input": {
      "harness": "utf8_hex primitive ASCII0 repeated2097153"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-payload-proxy",
    "input": {
      "harness": "parse text with throwingProxy payload"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-representation-proxy",
    "input": {
      "harness": "parse throwingProxy representation with primitivepayloadnull"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-accessors",
    "input": {
      "harness": "parse text with accessor/toString/Symbol.toPrimitive objectpayload"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-typedbytes",
    "input": {
      "harness": "parse utf8_hex with callerUint8Array payload"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-nullpayload",
    "input": {
      "harness": "parse text with nullpayload"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-numericpayload",
    "input": {
      "harness": "parse text with number1payload"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-wrongrepresentation",
    "input": {
      "harness": "parse unknownrepresentation json with stringnull"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-codec-proxy",
    "input": {
      "harness": "captureReader with throwingProxycodec and authenticreaderToken"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-reader-proxy",
    "input": {
      "harness": "captureReader with authenticcodec and throwingProxyreaderToken"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-reader-forged",
    "input": {
      "harness": "captureReader with authenticcodec and forgedtoken visiblebrandfields"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-reader-crossfactory",
    "input": {
      "harness": "captureReader with authenticcodecA and authenticreaderTokenB"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-codec-forged",
    "input": {
      "harness": "captureReader with forgedcodec getterparse plus authenticreaderToken"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-read-handle-proxy",
    "input": {
      "harness": "capturedReaderA.read throwingProxyhandle"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-read-handle-forged",
    "input": {
      "harness": "capturedReaderA.read callerAST objectkindnull"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-read-root-crossfactory",
    "input": {
      "harness": "capturedReaderA.read authenticrootB"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-read-child-crossfactory",
    "input": {
      "harness": "capturedReaderA.read authenticchildB obtainedfromcapturedReaderB"
    },
    "expected": {
      "error": "invalid_json_value",
      "caller_traps": 0
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-captured-reader",
    "input": {
      "harness": "capture originalReaderA; attemptreplace externalreadconfiguration with factoryB read; originalReaderA still readsrootA and rejectsrootB"
    },
    "expected": {
      "original_membership": true,
      "substitute_accepted": false,
      "original_callbacks_preserved": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-fresh-views",
    "input": {
      "harness": "read sameauthenticobjectroot twice; mutate frozenentrypair/array/descriptor/numbervalue and rescan"
    },
    "expected": {
      "fresh_descriptor": true,
      "all_nested_views_frozen": true,
      "original_graph_unchanged": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-input-mutation",
    "input": {
      "harness": "parse primitivevariable containing[1]; reassignoriginalvariable to[2] thenreadsamehandle"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "1"
            }
          }
        ]
      },
      "graph_unchanged": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-pure-scope",
    "input": {
      "harness": "close real unrelatedoperationScope afterparse; numeric/valuehandle stillauthenticbut no operationauthorization"
    },
    "expected": {
      "authentic_numeric_value": true,
      "codec_implies_grant": false,
      "operation_after_close": false
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-own-numeric-service-substitution",
    "input": {
      "harness": "Createcodec capturesoriginalacceptednumericfactory/read; parse exacttext[-0,18446744073709551615]; saveauthentichandle; replaceconsumer variable withforeignnumericfactory/getterservice (neverpassedtocodec); readoriginalhandle withoriginalcapturedreader"
    },
    "expected": {
      "tree": {
        "kind": "array",
        "items": [
          {
            "kind": "number",
            "value": {
              "class": "f64",
              "bits": "8000000000000000"
            }
          },
          {
            "kind": "number",
            "value": {
              "class": "u64",
              "decimal": "18446744073709551615"
            }
          }
        ]
      },
      "caller_traps": 0,
      "original_numeric_binding": true
    },
    "source_basis": "Explicit bounded privateprofile proposal, not public Rust limits; constructexactprimitive BEFORE invoking parser, expectedcounts independent"
  },
  {
    "case_id": "value-bound-raw-nodes-at",
    "input": {
      "harness": "text: firstrawcarrier stringvalue encodingarray65533zeros; rootcarrier2nodes + innerarray65534nodes =65536total"
    },
    "expected": {
      "root_kind": "array",
      "array_length": 65533,
      "parsed_nodes": 65536,
      "published": true,
      "final_graph_nodes": 65534
    },
    "source_basis": "Private sharedrawcarrierbudget explicitlydistinctsource perfrom_str reset; sourceonly exactarithmetic expectedbeforecode"
  },
  {
    "case_id": "value-bound-raw-depth-at",
    "input": {
      "harness": "text: firstrawcarrier stringvalue encoding126 nested arrays aroundnull; carrierobjectdepth1 + inner126 =127"
    },
    "expected": {
      "root_kind": "array",
      "final_graph_container_depth": 126,
      "maximum_shared_active_container_depth": 127,
      "published": true
    },
    "source_basis": "Private sharedrawcarrierbudget explicitlydistinctsource perfrom_str reset; sourceonly exactarithmetic expectedbeforecode"
  },
  {
    "case_id": "value-bound-raw-strings-at",
    "input": {
      "harness": "text: firstrawcarrier stringvalue encodingquotedASCIIa131056; key30 + carrierdecoded131058 + innerdecoded131056 =262144"
    },
    "expected": {
      "root_kind": "string",
      "decoded_utf8_bytes": 131056,
      "aggregate_decoded_string_utf8_bytes": 262144,
      "published": true
    },
    "source_basis": "Private sharedrawcarrierbudget explicitlydistinctsource perfrom_str reset; sourceonly exactarithmetic expectedbeforecode"
  },
  {
    "case_id": "value-bound-raw-strings-over",
    "input": {
      "harness": "text: samecarrier innerASCIIa131057; 30+131059+131057=262146"
    },
    "expected": {
      "error": "invalid_json_value",
      "partial_value_published": false
    },
    "source_basis": "Private sharedrawcarrierbudget explicitlydistinctsource perfrom_str reset; sourceonly exactarithmetic expectedbeforecode"
  },
  {
    "case_id": "value-raw-nested-carrier",
    "input": {
      "representation": "text",
      "payload": "{\"$serde_json::private::RawValue\":\"{\\\"$serde_json::private::RawValue\\\":\\\"1\\\"}\"}"
    },
    "expected": {
      "tree": {
        "kind": "number",
        "value": {
          "class": "u64",
          "decimal": "1"
        }
      }
    },
    "source_basis": "Actualraw_value KeyClassifier+recursivefrom_str on both firstkeys, all counters sharedprivateprofile"
  }
] as const;

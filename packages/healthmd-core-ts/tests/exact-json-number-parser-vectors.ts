/** Stage1 independent literal corpus. No parser/test implementation or Rust oracle executed.
 * Retained serde_json1.0.151 default non-float_roundtrip source stages are explicit.
 * Minimum packet literals preserved; mathematical bit witnesses are exact IEEE rational derivations.
 * Independent source/fixture review required before implementation; no candidate-produced expectations. */
import type * as Result from "effect/Result";
declare const ownedNumberBrand: unique symbol;
export interface OwnedJsonNumber { readonly [ownedNumberBrand]: true }
export interface ExactJsonNumberFailure { readonly _tag: "ExactJsonNumberFailure"; readonly code: "invalid_json_number" }
export type SourceNumber = { readonly class: "i64" | "u64"; readonly decimal: string } | { readonly class: "f64"; readonly bits: string };
export interface ExactJsonNumberParser {
  readonly parse: (representation: unknown, payload: unknown) => Result.Result<OwnedJsonNumber, ExactJsonNumberFailure>;
  readonly read: (handle: unknown) => Result.Result<SourceNumber, ExactJsonNumberFailure>;
}
export const numberParserContract = {
  "representation_literal": "serde_value_default",
  "max_token_code_units": 1024,
  "max_token_utf8_bytes": 1024,
  "grammar": "Complete ASCII JSON number token, no leading/trailing whitespace in this private token API. Optional minus, zero or nonzero digits, optional dot+nonemptydigits, optional e/E plus optional +/- +nonemptydigits. Full JSON whitespace remains value parser owner.",
  "classes": "Source positiveinteger U64; negative fittingnonzeroI64; -0,decimal,exponent,integer overflow/negativebelowi64 => finiteF64 or fixed failure. No i128/u128 widening.",
  "ownership": "Per-factory inaccessible WeakMap; check authentic handle membership before properties; frozen opaque handle. Original reader captured on factory creation; returns fresh immutable closed descriptor. Pure factory has no Effect Scope requirement; operation adapters separately own Scope/authority. No public export/deepimport/liveness grant from numeric validity.",
  "default_stages": [
    "u64 significand checked multiply/add; overflowing digit NOT consumed until long-integer loop, discarded remaining integer digits raise exponent",
    "decimal collects u64 digits and decrements exponent; overflow discards remaining decimal digits WITHOUT extending decimal exponent",
    "exponent requires digit, saturatingstarting+i32 arithmetic; overflow magnitude returns signedzero for zero/negative exponent, rejects positive nonzero",
    "u64->f64 IEEE nearest ties-even FIRST; rounded source literal POW10 constant; multiply/divide as separateIEEE operation; outside negative308 repeatedlydivide rounded1e308 and add308; apply sign LAST",
    "No global correctly-rounded decimal parse, JS Number token conversion or float_roundtrip substitution."
  ],
  "fixed_failure": {
    "_tag": "ExactJsonNumberFailure",
    "code": "invalid_json_number"
  },
  "ports": "createExactJsonNumberParser() => captured {parse(representation:unknown,payload:unknown):Result<OwnedJsonNumber,ExactJsonNumberFailure>,read(handle:unknown):Result<SourceNumber,ExactJsonNumberFailure>}; no source/scalar callback, I/O, Effect service replacement or caller coercion."
} as const;
export const numberParserVectors = [
  {
    "case_id": "number-u64-one",
    "input": "1",
    "expected": {
      "class": "u64",
      "decimal": "1"
    },
    "source_basis": "de.rs parse_number positive integer",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-i64-minus-one",
    "input": "-1",
    "expected": {
      "class": "i64",
      "decimal": "-1"
    },
    "source_basis": "de.rs negative integer",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-minus-zero",
    "input": "-0",
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "source_basis": "de.rs explicitly promotes -0 to F64",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-decimal-one",
    "input": "1.0",
    "expected": {
      "class": "f64",
      "bits": "3ff0000000000000"
    },
    "source_basis": "parse_decimal",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-exponent-one",
    "input": "1e0",
    "expected": {
      "class": "f64",
      "bits": "3ff0000000000000"
    },
    "source_basis": "parse_exponent",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-i64-min",
    "input": "-9223372036854775808",
    "expected": {
      "class": "i64",
      "decimal": "-9223372036854775808"
    },
    "source_basis": "negative wrapping boundary",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-u64-max",
    "input": "18446744073709551615",
    "expected": {
      "class": "u64",
      "decimal": "18446744073709551615"
    },
    "source_basis": "u64 max",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-unsafe-integer",
    "input": "9007199254740993",
    "expected": {
      "class": "u64",
      "decimal": "9007199254740993"
    },
    "source_basis": "no Number/JSON.parse rounding",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-u64-overflow",
    "input": "18446744073709551616",
    "expected": {
      "class": "f64",
      "bits": "43f0000000000000"
    },
    "source_basis": "default parse_long_integer, exactly2^64",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-negative-underflow",
    "input": "-1e-999",
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "source_basis": "negative exponent underflow preserves sign",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-positive-overflow",
    "input": "1e999",
    "expected": {
      "error": "invalid_json_number"
    },
    "source_basis": "finite overflow rejects",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-zero-huge-exponent",
    "input": "0e999999999999999999999",
    "expected": {
      "class": "f64",
      "bits": "0000000000000000"
    },
    "source_basis": "parse_exponent_overflow zero_significand",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-leading-zero",
    "input": "01",
    "expected": {
      "error": "invalid_json_number"
    },
    "source_basis": "strict JSON grammar",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-trailing-junk",
    "input": "1x",
    "expected": {
      "error": "invalid_json_number"
    },
    "source_basis": "complete token only",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-plus",
    "input": "+1",
    "expected": {
      "error": "invalid_json_number"
    },
    "source_basis": "no leading plus",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "number-caller-object",
    "input": {
      "harness": "throwing proxy/accessor/coercion object"
    },
    "expected": {
      "error": "invalid_json_number",
      "traps": 0
    },
    "source_basis": "primitive type before coercion",
    "status": "proposed_independent_literal_review_required",
    "packet_literal_preserved": true
  },
  {
    "case_id": "decimal-tenth",
    "input": "0.1",
    "stage_witness": {
      "u64_significand": "1",
      "decimal_exponent": -1,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "3fb999999999999a"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "3ff0000000000000"
      },
      {
        "operation": "divide",
        "decimal_power": 1,
        "rounded_power_bits": "4024000000000000",
        "bits": "3fb999999999999a"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "decimal-three-tenths",
    "input": "0.3",
    "stage_witness": {
      "u64_significand": "3",
      "decimal_exponent": -1,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "3fd3333333333333"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4008000000000000"
      },
      {
        "operation": "divide",
        "decimal_power": 1,
        "rounded_power_bits": "4024000000000000",
        "bits": "3fd3333333333333"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "long-fraction",
    "input": "0.123456789012345678901234567890",
    "stage_witness": {
      "u64_significand": "12345678901234567890",
      "decimal_exponent": -20,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "3fbf9add3746f65f"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "43e56a95319d63e1"
      },
      {
        "operation": "divide",
        "decimal_power": 20,
        "rounded_power_bits": "4415af1d78b58c40",
        "bits": "3fbf9add3746f65f"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "long-positive",
    "input": "1.23456789012345678901234567890",
    "stage_witness": {
      "u64_significand": "12345678901234567890",
      "decimal_exponent": -19,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "3ff3c0ca428c59fb"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "43e56a95319d63e1"
      },
      {
        "operation": "divide",
        "decimal_power": 19,
        "rounded_power_bits": "43e158e460913d00",
        "bits": "3ff3c0ca428c59fb"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "u64-overflow-dropped",
    "input": "18446744073709551619",
    "stage_witness": {
      "u64_significand": "1844674407370955161",
      "decimal_exponent": 1,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "43f0000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "43b999999999999a"
      },
      {
        "operation": "multiply",
        "decimal_power": 1,
        "rounded_power_bits": "4024000000000000",
        "bits": "43f0000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "i64-negative-underflow",
    "input": "-9223372036854775809",
    "stage_witness": {
      "u64_significand": "9223372036854775809",
      "decimal_exponent": 0,
      "negative": true
    },
    "expected": {
      "class": "f64",
      "bits": "c3e0000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "43e0000000000000"
      },
      {
        "operation": "multiply",
        "decimal_power": 0,
        "rounded_power_bits": "3ff0000000000000",
        "bits": "43e0000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "u64-max-decimal",
    "input": "18446744073709551615.0",
    "stage_witness": {
      "u64_significand": "18446744073709551615",
      "decimal_exponent": 0,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "43f0000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "43f0000000000000"
      },
      {
        "operation": "multiply",
        "decimal_power": 0,
        "rounded_power_bits": "3ff0000000000000",
        "bits": "43f0000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "integer-overflow-then-decimal",
    "input": "184467440737095516160.5",
    "stage_witness": {
      "u64_significand": "18446744073709551615",
      "decimal_exponent": 1,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "4424000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "43f0000000000000"
      },
      {
        "operation": "multiply",
        "decimal_power": 1,
        "rounded_power_bits": "4024000000000000",
        "bits": "4424000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "unsafe-integer-decimal",
    "input": "9007199254740993.0",
    "stage_witness": {
      "u64_significand": "90071992547409930",
      "decimal_exponent": -1,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "4340000000000001"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4374000000000001"
      },
      {
        "operation": "divide",
        "decimal_power": 1,
        "rounded_power_bits": "4024000000000000",
        "bits": "4340000000000001"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "max-finite-decimal",
    "input": "1.7976931348623157e308",
    "stage_witness": {
      "u64_significand": "17976931348623157",
      "decimal_exponent": 292,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "7fefffffffffffff"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "434feef63f97d79a"
      },
      {
        "operation": "multiply",
        "decimal_power": 292,
        "rounded_power_bits": "7c9008896bcf54fa",
        "bits": "7fefffffffffffff"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "over-max-finite",
    "input": "1.7976931348623159e308",
    "stage_witness": {
      "u64_significand": "17976931348623159",
      "decimal_exponent": 292,
      "negative": false
    },
    "expected": {
      "error": "invalid_json_number"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "434feef63f97d79c"
      },
      {
        "operation": "multiply",
        "decimal_power": 292,
        "rounded_power_bits": "7c9008896bcf54fa",
        "bits": "7ff0000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "min-normal-decimal",
    "input": "2.2250738585072014e-308",
    "stage_witness": {
      "u64_significand": "22250738585072014",
      "decimal_exponent": -324,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "0010000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4353c33b72569c64"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "0361c37937e08000"
      },
      {
        "operation": "divide",
        "decimal_power": 16,
        "rounded_power_bits": "4341c37937e08000",
        "bits": "0010000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "min-subnormal",
    "input": "5e-324",
    "stage_witness": {
      "u64_significand": "5",
      "decimal_exponent": -324,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "0000000000000001"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4014000000000000"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "0021fa182c40c60d"
      },
      {
        "operation": "divide",
        "decimal_power": 16,
        "rounded_power_bits": "4341c37937e08000",
        "bits": "0000000000000001"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "under-half-subnormal",
    "input": "2e-324",
    "stage_witness": {
      "u64_significand": "2",
      "decimal_exponent": -324,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "0000000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4000000000000000"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "000e61acf033d1a4"
      },
      {
        "operation": "divide",
        "decimal_power": 16,
        "rounded_power_bits": "4341c37937e08000",
        "bits": "0000000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "above-half-subnormal",
    "input": "3e-324",
    "stage_witness": {
      "u64_significand": "3",
      "decimal_exponent": -324,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "0000000000000001"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4008000000000000"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "00159283684dba76"
      },
      {
        "operation": "divide",
        "decimal_power": 16,
        "rounded_power_bits": "4341c37937e08000",
        "bits": "0000000000000001"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "negative-min-subnormal",
    "input": "-5e-324",
    "stage_witness": {
      "u64_significand": "5",
      "decimal_exponent": -324,
      "negative": true
    },
    "expected": {
      "class": "f64",
      "bits": "8000000000000001"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4014000000000000"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "0021fa182c40c60d"
      },
      {
        "operation": "divide",
        "decimal_power": 16,
        "rounded_power_bits": "4341c37937e08000",
        "bits": "0000000000000001"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "deep-underflow",
    "input": "1e-999",
    "stage_witness": {
      "u64_significand": "1",
      "decimal_exponent": -999,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "0000000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "3ff0000000000000"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "000730d67819e8d2"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "0000000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "negative-deep-underflow",
    "input": "-1e-999",
    "stage_witness": {
      "u64_significand": "1",
      "decimal_exponent": -999,
      "negative": true
    },
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "3ff0000000000000"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "000730d67819e8d2"
      },
      {
        "operation": "divide_by_rounded_1e308",
        "bits": "0000000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "power-positive",
    "input": "1e23",
    "stage_witness": {
      "u64_significand": "1",
      "decimal_exponent": 23,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "44b52d02c7e14af6"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "3ff0000000000000"
      },
      {
        "operation": "multiply",
        "decimal_power": 23,
        "rounded_power_bits": "44b52d02c7e14af6",
        "bits": "44b52d02c7e14af6"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "power-negative",
    "input": "1e-23",
    "stage_witness": {
      "u64_significand": "1",
      "decimal_exponent": -23,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "3b282db34012b252"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "3ff0000000000000"
      },
      {
        "operation": "divide",
        "decimal_power": 23,
        "rounded_power_bits": "44b52d02c7e14af6",
        "bits": "3b282db34012b252"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "large-cast-tie-even-down",
    "input": "9007199254740993e0",
    "stage_witness": {
      "u64_significand": "9007199254740993",
      "decimal_exponent": 0,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "4340000000000000"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4340000000000000"
      },
      {
        "operation": "multiply",
        "decimal_power": 0,
        "rounded_power_bits": "3ff0000000000000",
        "bits": "4340000000000000"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "large-cast-tie-even-up",
    "input": "9007199254740995e0",
    "stage_witness": {
      "u64_significand": "9007199254740995",
      "decimal_exponent": 0,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "4340000000000002"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "4340000000000002"
      },
      {
        "operation": "multiply",
        "decimal_power": 0,
        "rounded_power_bits": "3ff0000000000000",
        "bits": "4340000000000002"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "long-decimal-dropped-digits",
    "input": "0.1000000000000000055511151231257827021181583404541015625",
    "stage_witness": {
      "u64_significand": "10000000000000000555",
      "decimal_exponent": -20,
      "negative": false
    },
    "expected": {
      "class": "f64",
      "bits": "3fb999999999999a"
    },
    "independent_ieee_rounding_trace": [
      {
        "operation": "u64_to_f64",
        "bits": "43e158e460913d00"
      },
      {
        "operation": "divide",
        "decimal_power": 20,
        "rounded_power_bits": "4415af1d78b58c40",
        "bits": "3fb999999999999a"
      }
    ],
    "basis": "Primary default de.rs ordered stages; independent exact rational IEEE754 derivation, not candidate output or Rust oracle."
  },
  {
    "case_id": "integer-zero",
    "input": "0",
    "expected": {
      "class": "u64",
      "decimal": "0"
    },
    "basis": "Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "i64-max-as-u64",
    "input": "9223372036854775807",
    "expected": {
      "class": "u64",
      "decimal": "9223372036854775807"
    },
    "basis": "Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "positive-over-i64",
    "input": "9223372036854775808",
    "expected": {
      "class": "u64",
      "decimal": "9223372036854775808"
    },
    "basis": "Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "negative-i64-neighbor",
    "input": "-9223372036854775807",
    "expected": {
      "class": "i64",
      "decimal": "-9223372036854775807"
    },
    "basis": "Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "negative-safe-integer",
    "input": "-9007199254740993",
    "expected": {
      "class": "i64",
      "decimal": "-9007199254740993"
    },
    "basis": "Primary parse_integer/parse_number exact integer range/class; raw string precision."
  },
  {
    "case_id": "negative-decimal-zero",
    "input": "-0.0",
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "negative-exponent-zero",
    "input": "-0E+0",
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "positive-exponent-plus",
    "input": "1e+00",
    "expected": {
      "class": "f64",
      "bits": "3ff0000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "positive-uppercase-exponent",
    "input": "1E0",
    "expected": {
      "class": "f64",
      "bits": "3ff0000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "zero-positive-i32-overflow",
    "input": "0e2147483648",
    "expected": {
      "class": "f64",
      "bits": "0000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "negative-zero-positive-i32-overflow",
    "input": "-0e2147483648",
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "zero-negative-i32-overflow",
    "input": "0e-2147483648",
    "expected": {
      "class": "f64",
      "bits": "0000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "negative-positive-i32-underflow",
    "input": "-1e-2147483648",
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "negativezero-underflow",
    "input": "-0e-99999",
    "expected": {
      "class": "f64",
      "bits": "8000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "fraction-trailing-zero",
    "input": "1.00000000000000000000",
    "expected": {
      "class": "f64",
      "bits": "3ff0000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "truncated-fraction-not-integer",
    "input": "1.00000000000000000001",
    "expected": {
      "class": "f64",
      "bits": "3ff0000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "bound-exponent-zeros",
    "input": "1e00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "expected": {
      "class": "f64",
      "bits": "3ff0000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "bound-zero-fraction",
    "input": "0.00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "expected": {
      "class": "f64",
      "bits": "0000000000000000"
    },
    "basis": "Default source decimal/exponent stages, exact zero/one or signed underflow.1024 primitive cap private only."
  },
  {
    "case_id": "empty",
    "input": "",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "decimal-dot",
    "input": ".",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "no-leading-digit",
    "input": ".1",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "no-fraction-digit",
    "input": "1.",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "negative-no-digit",
    "input": "-",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "exponent-no-digit",
    "input": "1e",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "exponent-sign-no-digit",
    "input": "1e-",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "double-sign",
    "input": "--1",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "infinity",
    "input": "Infinity",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "nan",
    "input": "NaN",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "hex",
    "input": "0x1",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "whitespace-leading",
    "input": " 1",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "whitespace-trailing",
    "input": "1\n",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "newline-inside",
    "input": "1\n0",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "unicode-minus",
    "input": "−1",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "unicode-digit",
    "input": "١",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "numeric-separator",
    "input": "1_000",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "negative-leading-zero",
    "input": "-01",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "negative-leading-zero-fraction",
    "input": "-00.1",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "multiple-decimal",
    "input": "1.2.3",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "multiple-exponent",
    "input": "1e1e1",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "i32-exponent-overflow",
    "input": "1e2147483648",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "positive-i32-exp-max",
    "input": "1e2147483647",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "token-over-private-bound",
    "input": "0.000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
    "expected": {
      "error": "invalid_json_number"
    },
    "basis": "Complete primitive numeric token grammar/private1024 cap or primary finite exponent overflow. Surrounding whitespace rejected by private token API, not full serde from_str policy."
  },
  {
    "case_id": "nonprimitive-proxy",
    "input": {
      "harness": "throwing Proxy object"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "nonprimitive-getter",
    "input": {
      "harness": "object with accessor/toString/Symbol.toPrimitive traps"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "nonprimitive-array",
    "input": {
      "harness": "array"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "nonprimitive-null",
    "input": {
      "harness": "null"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "wrong-number-payload",
    "input": {
      "harness": "numeric1"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "wrong-bool-payload",
    "input": {
      "harness": "true"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "wrong-bigint-payload",
    "input": {
      "harness": "bigint1"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "wrong-representation-object",
    "input": {
      "harness": "throwing Proxy representation"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "wrong-representation-string",
    "input": {
      "harness": "signed_integer"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "huge-primitive-before-scan",
    "input": {
      "harness": "string1millioncodeunits"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Primitive type/length before coercion/reflection/scanning/bigint/allocation; fixed safe error."
  },
  {
    "case_id": "ownership-foreign-factory",
    "input": {
      "harness": "read authentic other factory handle"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Pure factory membership before properties; operation Scope separate; no injected-service reprovide or implicit data authority."
  },
  {
    "case_id": "ownership-proxy-read",
    "input": {
      "harness": "read throwing proxy handle"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Pure factory membership before properties; operation Scope separate; no injected-service reprovide or implicit data authority."
  },
  {
    "case_id": "ownership-forged-brand",
    "input": {
      "harness": "read caller object with matching visible fields/brand"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Pure factory membership before properties; operation Scope separate; no injected-service reprovide or implicit data authority."
  },
  {
    "case_id": "ownership-captured-reader",
    "input": {
      "harness": "save original bound reader, later substitute unrelated reader config"
    },
    "expected": {
      "original_factory_membership": true,
      "substitute_accepted": false
    },
    "basis": "Pure factory membership before properties; operation Scope separate; no injected-service reprovide or implicit data authority."
  },
  {
    "case_id": "ownership-fresh-view",
    "input": {
      "harness": "mutate returned descriptor then read same handle"
    },
    "expected": {
      "immutable_original": true,
      "fresh_view": true
    },
    "basis": "Pure factory membership before properties; operation Scope separate; no injected-service reprovide or implicit data authority."
  },
  {
    "case_id": "ownership-unrelated-factory-scope",
    "input": {
      "harness": "operation scope closes while pure numeric handle still exists"
    },
    "expected": {
      "codec_implies_authority": false,
      "operation_after_close": false
    },
    "basis": "Pure factory membership before properties; operation Scope separate; no injected-service reprovide or implicit data authority."
  },
  {
    "case_id": "no-scalar-coercion",
    "input": {
      "harness": "pass owned descriptor/object directly as primitive payload"
    },
    "expected": {
      "error": "invalid_json_number",
      "caller_traps": 0
    },
    "basis": "Pure factory membership before properties; operation Scope separate; no injected-service reprovide or implicit data authority."
  }
] as const;
export const sourceOracleProposal = {
  "status": "proposed_unexecuted_requires_root_clearance",
  "tuple": {
    "host": "aarch64-apple-darwin",
    "rust_toolchain_directory": "1.85.0-aarch64-apple-darwin",
    "cargo_and_rustc_binary_pins": {
      "cargo": {
        "path": "/Users/codybontecou/.rustup/toolchains/1.85.0-aarch64-apple-darwin/bin/cargo",
        "sha256": "dcfda0c91c578ea2a199cb2af9c53796711607cbd8f8ea618dc87dc0febae2cf",
        "bytes": 25357080
      },
      "rustc": {
        "path": "/Users/codybontecou/.rustup/toolchains/1.85.0-aarch64-apple-darwin/bin/rustc",
        "sha256": "cf4750269faa6c5eba9489e0b92850e2de7e260489d69d89bcfaf23f9fe46015",
        "bytes": 414920
      }
    },
    "serde_json": "1.0.151",
    "serde_json_archive_sha256": "c841b55ecdae098c80dcae9cf767f6f8a0c2cdb3416bbef72181df4d0fe73f14",
    "selected_declared_features": [
      "std",
      "raw_value"
    ],
    "negative_feature_requirements": [
      "float_roundtrip",
      "preserve_order",
      "arbitrary_precision",
      "unbounded_depth"
    ]
  },
  "feature_closure_verification": {
    "commands": [
      {
        "cwd": ".",
        "argv": [
          "/Users/codybontecou/.rustup/toolchains/1.85.0-aarch64-apple-darwin/bin/cargo",
          "metadata",
          "--offline",
          "--locked",
          "--format-version",
          "1",
          "--filter-platform",
          "aarch64-apple-darwin",
          "--manifest-path",
          "packages/healthmd-core-rust/Cargo.toml"
        ]
      },
      {
        "cwd": ".",
        "argv": [
          "/Users/codybontecou/.rustup/toolchains/1.85.0-aarch64-apple-darwin/bin/cargo",
          "metadata",
          "--offline",
          "--locked",
          "--format-version",
          "1",
          "--filter-platform",
          "aarch64-apple-darwin",
          "--manifest-path",
          "apps/cli/Cargo.toml"
        ]
      }
    ],
    "required_review": "After separate metadata clearance, inspect complete resolve nodes active features for exact serde_json package across both selected workspace default graphs and selected core/MCP consumer dependency closure; audit every dependency archive/license/hash before executable oracle. If declared hypothesis differs, STOP and report; no feature substitution or expected regeneration. Lock alone not proof."
  },
  "proposed_private_oracle": {
    "path": "/private/tmp/healthmd-serde-json-number-source-oracle",
    "manifest": "Isolated scratch Rust binary, exactserde_json1.0.151 std/raw_value only, no newproductRust/production/source edits. Freeze small source/manifest/lock with independent review BEFORE execution.",
    "argv": [
      "/Users/codybontecou/.rustup/toolchains/1.85.0-aarch64-apple-darwin/bin/cargo",
      "run",
      "--offline",
      "--locked",
      "--release",
      "--manifest-path",
      "/private/tmp/healthmd-serde-json-number-source-oracle/Cargo.toml",
      "--",
      "/private/tmp/healthmd-exact-number-source-oracle-inputs.json"
    ],
    "environment": {
      "RUSTC": "/Users/codybontecou/.rustup/toolchains/1.85.0-aarch64-apple-darwin/bin/rustc",
      "CARGO_NET_OFFLINE": "true",
      "CARGO_HOME": "/Users/codybontecou/.cargo",
      "CARGO_TARGET_DIR": "/private/tmp/healthmd-serde-json-number-source-oracle-target"
    },
    "supervision_proposal": "180seconds/16MiB combined output, own process group only; one scratchtarget, no copiedcache/oldtarget/newdependency fetch. All graph/tool/archive/license provenance reviewed before execution.",
    "input_policy": "Only frozen synthetic literal numeric tokens; Value from_str success class + to_bits/exactinteger, fixed error classification. No host data/source/output/health access.",
    "result_policy": "Supplement existing source/math justification after independent review; disagreement stops admission, never automatic regeneration of accepted expectations."
  },
  "cache_policy": "Reuse approved source/archive cache READ; pin provenance graph first. Do not execute rustup/download/update/install/provider/network here. Existing proposed tool binaries hashed only, no Rust/version/metadata/build/oracle execution."
} as const;

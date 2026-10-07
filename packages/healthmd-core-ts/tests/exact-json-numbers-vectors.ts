/** Frozen before implementation; expected lexemes are primary literals or exact mathematical cases.
 * Interface proposed: serializeExactJsonNumber(representation: unknown, payload: unknown):
 * Result.Result<Uint8Array, { readonly _tag: "ExactJsonNumberFailure";
 * readonly code: "invalid_json_number" }>.
 * Input: primitive representation binary64/signed_integer/unsigned_integer plus primitive payload;
 * finite 16 lowercase hex bits or canonical i64/u64 decimal. Success owns fresh ASCII UTF-8 bytes.
 * No object reflection/coercion/callbacks; nonprimitive, nonfinite and widened integer share fixed failure.
 * Fixture records below are harness data, not object admission by this primitive API.
 * Primary: zmij 1.0.23 tests/test.rs dtoa_test (literal expected text), src/lib.rs f64
 * FIXED_DEC_EXP=-5..=15; serde_json 1.0.151 ser.rs write_f64/write_i64/write_u64.
 * Bits for upstream decimal literals independently decoded with Python struct.pack('>d', float(literal));
 * Python formatting was not used for expected text. Threshold/IEEE limit expectations require review.
 */
export const binary64Vectors = [
  // Primary dtoa_test::zero, small_int, subnormal.
  ["zero", "0000000000000000", "0.0"],
  ["negative-zero", "8000000000000000", "-0.0"],
  ["one", "3ff0000000000000", "1.0"],
  ["min-subnormal", "0000000000000001", "5e-324"],
  ["subnormal-two", "0000000000000002", "1e-323"],
  ["subnormal-24", "0000000000000018", "1.2e-322"],
  ["subnormal-25", "0000000000000019", "1.24e-322"],
  ["subnormal-2498", "00000000000009c2", "1.234e-320"],
  ["near-min-normal", "000ffffffffffffe", "2.2250738585072004e-308"],
  // Primary normal/shorter/single_candidate/boundary_cases/fixed_with_zeros.
  ["planck", "390b860bde023111", "6.62607015e-34"],
  ["half-ulp", "42fef283c71d933a", "544431068535091.6"],
  ["shorter-under", "91275e29dc2e6848", "-4.932096661796888e-226"],
  ["shorter-over", "47508efb3d209dd2", "3.439070283483335e+35"],
  ["single-under", "3c930aff7a5639c6", "6.606854224493745e-17"],
  ["single-over", "4cc2eaa1a013a2e0", "6.079537928711555e+61"],
  ["boundary-small", "0d17c0747bd76fa1", "1.3588129002659584e-245"],
  ["boundary-even", "3e60000000000000", "2.9802322387695312e-8"],
  ["boundary-next-power", "3e70000000000000", "5.960464477539063e-8"],
  ["boundary-large", "4d73de005bd620df", "1.3076622631878654e+65"],
  ["boundary-tie-down", "3ea4000000000000", "5.960464477539062e-7"],
  ["fixed-zeros", "40e5194000000000", "43210.0"],
  ["fixed-fraction", "40e5194333333333", "43210.1"],
  ["fixed-power", "40c3880000000000", "10000.0"],
  ["fixed-negative", "c3351ce328dc941a", "-5942736479622170.0"],
  // IEEE exact intervals + primary lexical policy, independently reviewed mathematical expectations.
  ["min-normal", "0010000000000000", "2.2250738585072014e-308"],
  ["max-finite", "7fefffffffffffff", "1.7976931348623157e+308"],
  ["fixed-lower", "3ee4f8b588e368f1", "0.00001"],
  ["scientific-lower", "3eb0c6f7a0b5ed8d", "1e-6"],
  ["fixed-upper", "430c6bf526340000", "1000000000000000.0"],
  ["scientific-upper", "4341c37937e08000", "1e+16"],
  ["decimal-carry-inclusive", "44b52d02c7e14af6", "1e+23"],
  ["one-predecessor", "3fefffffffffffff", "0.9999999999999999"],
  ["one-successor", "3ff0000000000001", "1.0000000000000002"],
] as const;
export const integerVectors = [
  ["signed_integer", "0"], ["signed_integer", "-1"],
  ["signed_integer", "-9223372036854775808"], ["signed_integer", "9223372036854775807"],
  ["unsigned_integer", "0"], ["unsigned_integer", "18446744073709551615"],
] as const;
export const rejectedVectors: readonly unknown[] = [
  null, 1, "1", {},
  { representation: "binary32", bits: "3f800000" },
  ...["7ff0000000000000", "fff0000000000000", "7ff8000000000000", "7ff0000000000001",
    "3FF0000000000000", "3ff000000000000", " 3ff0000000000000"].map(bits => ({ representation: "binary64", bits })),
  ...["-0", "01", "+1", "1.0", "1e0", "", "9223372036854775808", "-9223372036854775809",
    "170141183460469231731687303715884105727"].map(decimal => ({ representation: "signed_integer", decimal })),
  ...["-1", "18446744073709551616", "340282366920938463463374607431768211455"].map(decimal => ({ representation: "unsigned_integer", decimal })),
] as const;

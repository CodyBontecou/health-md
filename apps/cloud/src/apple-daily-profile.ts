// v10 changes WHOOP supplementation, not these reviewed Apple Health summaries.
// Never infer compatibility from ordering: unified daily v9 remains reserved.
export function isReviewedAppleDailyVersion(value: unknown): value is 8 | 10 {
  return value === 8 || value === 10;
}

# Five free exports and the next export journey

Status: implemented in source; release and store deployment are separate.

## Outcome

Keep Apple Individual Lifetime at $19.99, using StoreKit localized prices. Do not change Google Play product pricing. Reduce counted free actions from ten to five on iOS/iPadOS and Google Play Android. Preserve existing usage and purchased/grandfathered access. Free macOS companion and F-Droid Full Access are unchanged. An action still counts once regardless of dates/files. Export schemas and protocol versions do not change.

After the first completed free export, offer a dismissible next step to review daily scheduling. Opening Schedule never enables a schedule or changes its destination. Apple scheduled runs use the same free allowance; Google Play scheduling still requires lifetime access and the guide says so. After the third completed free export, offer lifetime access through the normal purchase review flow with two actions remaining. Dismissal consumes no extra action. Do not replay earlier milestones for existing users whose counters have passed them. Unlocking clears pending guidance. Android partial exports retain accounting and diagnostics without showing a success guide.

## Measurement

October 1–14 mature, previously unpaid iOS activation cohort: 139 activated, 105 saw a paywall within seven days, 31 started purchasing, 25 bought. Of the 114 non-buyers, 97 exported successfully but only 20 previewed or exported on another day. These observations are descriptive.

Start the experiment when a release containing these changes ships, not on the source-edit date. Compare release/version cohorts with equal seven-day follow-up and exclude previous purchasers. Measure another-day export, paywall-to-purchase-start, purchase completion, net Apple proceeds, refunds, and review/support quality. Apple reuses bounded upgrade-prompt events with milestones 1 (schedule guidance) and 3 (lifetime offer). Android retains its existing onboarding-only telemetry boundary; post-export prompt analytics require a separately reviewed lifecycle implementation. Validate Android through device QA and store commerce reports in the meantime. No health values, files, paths, or user text enter analytics.

The quota and prompt changes are one combined intervention. Do not attribute results to price, quota or copy independently. Keep $19.99 while gathering mature cohorts. Previously accounted durable jobs retain their existing resume permission even after the allowance is exhausted.

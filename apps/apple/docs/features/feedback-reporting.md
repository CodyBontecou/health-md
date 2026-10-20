# Feedback reporting failure handling

## Outcome and scope

When an app-side feedback handoff fails, explain the failure and let the user
write, select, and copy a local report with the support address, GitHub URL,
template, and non-identifying diagnostics. Copying requires no browser, mail
client, network, or account. The user must submit the copied text later or on
another device; Health.md does not silently transmit or persist it.

Apple settings (iPhone/iPad, Mac General settings, and the legacy Mac feedback
tab) and the Mac destination setup card share `FeedbackReporter`. iOS uses the asynchronous URL-opening completion;
macOS checks the synchronous workspace result. A successful handoff is not proof
of mail delivery or GitHub issue submission. There is no submission-success UI.

The in-app iOS mail delegate forwards its result and error before dismissal.
Failed completion or a non-nil error schedules the local fallback **after** the
compose sheet dismisses. Sent (queued by Mail), saved, and cancelled without an
error do not show failure UI. The sheet explains that custom text entered in
Mail is not exposed to Health.md and must be re-entered if needed. Report text
is editable locally and must be copied before closing. Raw error descriptions
are neither displayed nor logged. No health data is attached automatically.

## Parity and compatibility

Android already catches `ActivityNotFoundException` and shows a no-app toast in
`presentation/common/FeedbackHelper.kt`, but has no independent local fallback.
There is no Health Connect blocker; this Apple-scoped repair stages the local
fallback for the next Android support-settings update. The inventory records
`support.local-reporting-fallback` as `planned`, with Apple available and that
concrete Android target. No Android runtime behavior changes here; its inventory
test is updated to account for the staged capability.

Version impact: internal UI/error handling only. No export schema, platform
profile, direct protocol, shared-core ABI, settings migration, or stored data
changes. Existing mailto and GitHub template contents remain compatible. CLI,
website, Rust, and the external Obsidian plugin consume no changed runtime
contract. The native registry importer excludes `support.*` UI-only capabilities
from core projections: the pinned metric registry and semantic/render fixtures
remain byte-identical. Core CI exercises that ownership boundary in
`scripts/tests/test_import_native_registry.py`; contract CI validates the additive
parity inventory and its updated manifest hash.

## SDK evidence

Public Apple references consulted for the adapters:

- [UIApplication.open(_:options:completionHandler:)](https://developer.apple.com/documentation/uikit/uiapplication/open(_:options:completionhandler:)):
  completion runs asynchronously on the main thread and reports whether the URL
  opened; no capable app produces `false`.
- [NSWorkspace.open(_:)](https://developer.apple.com/documentation/appkit/nsworkspace/open(_:)):
  returns `true` if the location opened and `false` otherwise.
- [Mail compose delegate](https://developer.apple.com/documentation/messageui/mfmailcomposeviewcontrollerdelegate/mailcomposecontroller(_:didfinishwith:error:)):
  dismiss the controller; sending queues mail, and queueing errors appear in the
  error parameter. This is not a delivery receipt.

## Regression coverage and remaining QA

`HealthMdTests/Utilities/FeedbackReporterTests.swift` injects failing, successful,
and deferred URL openers, verifies preserved URL/template data, and checks that
fallback does not retry another external app. On iOS it injects actual
`MFMailComposeResult` cases and errors to cover failed/sent/cancelled/saved,
post-dismissal presentation, one-time consumption, and sanitization. Xcode's
synchronized test group registers the file in `HealthMdTests`; Apple CI runs it
in both the iOS test and macOS coverage schemes without an `only-testing` filter.
Android CI runs the inventory governance test and shared-contract validation.

The reported inability to submit a bug report was not reproduced, and no root
cause for that user report is asserted. Unit tests reproduce only the previously
silent app-side failures. Hardware/runtime QA remains:

1. iPhone/iPad: unavailable Mail, rejected browser/email handoffs, and Mail
   failed completion; verify the fallback appears after dismissal, remains
   usable with large text/Dynamic Type, and Copy Report pastes the edited text.
2. Confirm sent, saved, cancelled, and interactive sheet dismissal do not show
   a failure; test a configured real Mail account without claiming delivery.
3. Mac: rejected browser/mail handoffs, fallback sizing/accessibility, and
   copying edited text with a real pasteboard. Check successful handlers.
4. Verify browser opening is described only as opening a template, and finish
   any real GitHub submission manually. Keep the investigation issue open.

# Community Feedback

## Status

- **Docs status:** draft
- **Video priority:** low
- **Primary screen:** Settings → Support
- **Source files:** `HealthMd/iOS/ContentView.swift`, `HealthMd/Shared/Utilities/FeedbackHelper.swift`, `HealthMd/iPad/iPadSettingsView.swift`, `HealthMd/macOS/Views/MacSettingsView.swift`

## What it does

Community Feedback gives users direct ways to contact the developer from inside Health.md. Users can send a pre-filled support email or open a pre-filled GitHub issue for bugs and feature requests.

The generated message includes non-identifying diagnostics: app version, build number, platform, OS version, and broad device type. It does not attach HealthKit data, exported files, or vault contents.

## Who it is for

- Users who found a bug and want to report it with useful context.
- Users who have questions about export setup, scheduling, sync, or purchases.
- Users who want to request features or discuss Obsidian workflows.
- TestFlight users sending actionable feedback before release.

## Where to find it

1. Open Health.md.
2. Go to **Settings**.
3. Find the support/feedback section.
4. Choose **Send Feedback** for email or **Report a Bug** for GitHub.

On macOS, feedback actions are also available from the settings window.

## Prerequisites

- An email client configured, or a browser available for GitHub issues.
- Internet connection to send email or open GitHub.
- For GitHub issues, a GitHub account may be required to submit.

## Setup

There is no setup inside Health.md.

To send feedback:

1. Tap **Send Feedback**.
2. If Mail is configured, Health.md opens an in-app compose sheet.
3. If in-app Mail is not available, Health.md opens a `mailto:` link in your default mail app.
4. Write your question, idea, or issue above the diagnostics block.
5. Send the email.

To report a bug:

1. Tap **Report a Bug**.
2. Health.md opens a new issue in `CodyBontecou/health-md`.
3. Fill in what happened, steps to reproduce, and expected behavior.
4. Submit the issue.

## Example diagnostics block

```text
---
App: Health.md 1.8.2 (123)
Platform: iOS Version 18.4 (Build ...)
Device: iPhone
```

This block is intentionally small so it helps debug app/platform issues without exposing health records.

## Tips

- For export problems, include the export date, selected formats, and the exact error shown in Export History.
- For sync problems, include both device names and whether they were on the same Wi-Fi network.
- For scheduled-export problems, mention whether the iPhone was locked at the scheduled time.
- For privacy-sensitive issues, use email instead of a public GitHub issue.
- Do not paste exported health files into a public issue unless you intentionally want to share them.

## Troubleshooting

| Problem | Likely cause | Fix |
|---|---|---|
| Email compose does not open | Mail is not configured on the device | Use the mailto fallback or copy the support email: `cody@isolated.tech`. |
| GitHub issue page opens but cannot submit | You are not signed in to GitHub | Sign in or send feedback by email instead. |
| Diagnostics look too limited | Health.md only includes non-identifying app/device info | Manually add relevant details, but avoid sharing private health data. |
| Browser/email app does not open | Device restrictions or no default handler | Try again from another device or contact support manually. |
| Need private support | GitHub issues are public | Use **Send Feedback** email. |

## Video outline

- **Suggested title:** How to Get Help and Report Bugs in Health.md
- **Hook:** “A good bug report helps fix export, sync, and scheduling issues faster.”
- **Demo flow:**
  1. Open Settings.
  2. Tap Send Feedback and show the pre-filled diagnostics.
  3. Return and tap Report a Bug.
  4. Show the GitHub issue template.
  5. Explain what to include for export, sync, and schedule issues.
- **Key screenshot/recording moments:** support section, mail compose sheet, diagnostics block, GitHub issue template.
- **CTA / next video:** “Next, we’ll walk through Export History so you can include the exact failure reason.”

## Implementation notes

- `FeedbackHelper.supportEmail` is `cody@isolated.tech`.
- `FeedbackHelper.githubRepo` is `CodyBontecou/health-md`.
- `diagnosticsBlock` includes app version/build, platform OS version, and device class.
- iOS uses `MFMailComposeViewController` when available and falls back to a `mailto:` URL.
- GitHub feedback opens `https://github.com/CodyBontecou/health-md/issues/new` with a pre-filled body.

# Health.md Feature Video Series Plan

This is the companion planning doc for the feature docs in this directory. Each episode should showcase one clear user outcome, not every setting in the app.

## Series promise

**Health.md turns Apple Health into private, local Markdown data you can use in Obsidian.**

Every video should reinforce:

- local-first health data ownership;
- Obsidian-native workflows;
- practical exports viewers can reproduce immediately;
- one feature per video, with links to the next deeper feature.

## Reusable episode structure

1. **Hook, 5–10 seconds** — show the end result first.
2. **Problem, 15–30 seconds** — why this feature matters.
3. **Setup, 60–120 seconds** — exact taps/settings.
4. **Export/demo, 60–180 seconds** — run the feature and show the output.
5. **Tips/limitations, 30–60 seconds** — permission, locked-device, path, or format caveats.
6. **CTA, 10 seconds** — link to docs, App Store, GitHub, next video.

## Episode roadmap

| # | Episode | Primary feature doc | Outcome | Priority |
|---:|---|---|---|---|
| 1 | Health.md Beginner Walkthrough: Apple Health → Obsidian | [Onboarding](./onboarding.md) + [Manual Export](./manual-export.md) | Viewer exports first Markdown file. | High |
| 2 | How to Export Apple Health Data to Markdown | [Markdown Export](./markdown-export.md) | Viewer understands metrics, date range, and output file. | High |
| 3 | Append Apple Health Data to Your Obsidian Daily Note | [Daily Note Injection](./daily-note-injection.md) | Viewer sees daily note frontmatter populated. | High |
| 4 | Use Apple Health Data in Obsidian Bases | [Obsidian Bases](./obsidian-bases.md) | Viewer builds a health Base table. | High |
| 5 | Customize Health.md File Names, Folders, and Templates | [Filename Templates](./filename-templates.md) + [Folder Organization](./folder-organization.md) | Viewer avoids messy vault structure. | High |
| 6 | Automate Health.md with Scheduled Exports | [Scheduled Exports](./scheduled-exports.md) | Viewer enables recurring exports and understands retry behavior. | High |
| 7 | Run Health.md from Apple Shortcuts | [Apple Shortcuts](./apple-shortcuts.md) | Viewer builds Shortcuts automations. | High |
| 8 | Track Mood / State of Mind in Obsidian | [Mood / State of Mind](./mood-state-of-mind.md) | Viewer exports State of Mind daily + individual mood files. | High |
| 9 | Export Individual Health Entries, Not Just Daily Summaries | [Individual Entry Tracking](./individual-entry-tracking.md) | Viewer creates timestamped files for mood, symptoms, workouts, vitals. | High |
| 10 | Workout Deep Dive: Pace, HR, Power, Cadence, Splits | [Workout Details](./workout-details.md) | Viewer exports richer workout records. | Medium |
| 11 | Use Your Mac as a Local Destination for iPhone Health.md Exports | [Mac Destination](./mac-sync.md) | Viewer configures on iPhone and writes files to a Mac folder. | High |
| 12 | Health.md Privacy Architecture: Where Your Data Goes | [Privacy and Local-First Design](./privacy-local-first.md) | Viewer trusts local-first architecture and scheduling-worker boundaries. | High |

## B-roll / capture checklist

Capture these once and reuse across episodes:

- Health.md app icon / home screen open.
- Export tab idle state.
- Health Metrics selection screen.
- Export Formats toggles.
- Path preview row.
- Export running/progress state.
- Successful export toast.
- Obsidian vault before and after export.
- Generated Markdown file.
- Generated Bases frontmatter file.
- Schedule tab with next export.
- Shortcuts action list.
- Settings → Discord / feedback / GitHub issue.
- Mac Destination screen with folder readiness.
- iPhone Export target selector showing Connected Mac.

## Naming pattern

Use titles that target the concrete search query first:

- “Apple Health to Obsidian: ...”
- “Export Apple Health to Markdown: ...”
- “Obsidian Bases with Apple Health Data: ...”
- “Automate Apple Health Exports with Shortcuts: ...”

Avoid titles that only say “Health.md feature tour” because they do not match search intent.

## CTA pattern

End each video with one of:

- “Download Health.md on the App Store.”
- “The app is open source — GitHub link is below.”
- “If you want this workflow, the written guide is linked below.”
- “Next video: [specific next feature].”

## Notes for filming

- Use realistic but non-sensitive sample data when possible.
- Blur personal Health data if filming a real device.
- For Shortcuts and scheduled exports, verify on a real iPhone before filming.
- For Daily Note Injection and Bases, prepare a small clean demo vault so the before/after is obvious.

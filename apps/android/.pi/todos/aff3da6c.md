{
  "id": "aff3da6c",
  "title": "P2: Android accessibility parity audit and fixes",
  "tags": [
    "android",
    "parity",
    "accessibility",
    "ui",
    "p2"
  ],
  "status": "closed",
  "created_at": "2026-06-05T19:36:18.168Z"
}

Completed Android accessibility parity pass.

Reworked shared custom buttons/cards away from pointer-only handlers to Compose clickable semantics with button roles, enforced 48dp touch targets on shared secondary/icon buttons, added labels to icon-only schedule/frontmatter actions, improved export progress announcements, and documented the audit/follow-up limitations in `docs/accessibility-android.md`.

Validation: `./gradlew testDebugUnitTest --no-daemon` passed.

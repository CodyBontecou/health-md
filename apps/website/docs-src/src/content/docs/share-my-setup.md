---
title: "Share My Setup"
description: "Review the development-only v2 profile-transfer workflow without health data, credentials, purchases, or device trust."
---

<div class="availability preview"><strong>Development preview · not release-qualified</strong><p>The v2 contract remains pre-canonical and planned until device interoperability and accessibility checks finish. Do not rely on it in production.</p></div>

Share My Setup packages one or more profiles. It transfers metrics, formats, naming, organization, and destination intent. It never includes health data, tokens, real folder access, pairings, purchases, history, or jobs.

1. On the source, open **Settings → Share My Setup** and export the v2 file.
2. Open it on the target and review every profile.
3. Choose **Add** or **Replace**.
4. Rebind the folder, API with credentials, or Mac locally.
5. Apply and test a small export.

The transaction is atomic and offers one **Undo**. Profiles remain blocked until their destination is rebound; imported schedules are disabled. Current development source writes only `healthmd.shared_setup` v2 and rejects v1.

<div class="related"><a href="/docs/export-profiles/"><span>Profiles</span>Understand frozen settings.</a><a href="/docs/guides/platform-features/"><span>Status</span>Review platform qualification.</a></div>

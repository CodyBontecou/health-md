# Monorepo source revisions

Recorded on 2026-07-24 before history import.

| Component | Source repository | Source revision | Destination | Import method |
| --- | --- | --- | --- | --- |
| Apple | `https://github.com/CodyBontecou/health-md.git` | `a968183011e29b07224739920e8b5305928cb49f` | `apps/apple` | Canonical history plus `git mv` |
| CLI | `https://github.com/CodyBontecou/healthmd-cli.git` | `0905f1278644d2b17d1827d5af0f3fa34e7401a8` | `apps/cli` | Filtered default-branch history |
| Android | `https://github.com/CodyBontecou/health-md-android.git` | `95e7716809296ff29331a0f1d706dc7948c0d1e3` | `apps/android` | Filtered default-branch history |
| Website | `https://github.com/CodyBontecou/obsidianhealth` | `7eb4a5038d1131b7fa110865448bdb6f3c467ecb` | `apps/website` | Filtered default-branch history |
| Obsidian plugin | `https://github.com/CodyBontecou/health-md-visualizations.git` | External | Not imported | Remains an external integration |

All four imported source worktrees were clean and synchronized with `origin/main` when recorded. Original repositories remain the authority for pre-migration commit hashes and release records.

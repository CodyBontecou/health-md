# Monorepo source revisions

Primary component revisions were recorded on 2026-07-24 before history import. The wake Worker
record was appended during its 2026-09-04 import.

| Component | Source repository | Source revision | Rewritten head | Destination | Import method |
| --- | --- | --- | --- | --- | --- |
| Apple | `https://github.com/CodyBontecou/health-md.git` | `a968183011e29b07224739920e8b5305928cb49f` | Unchanged | `apps/apple` | Canonical history plus `git mv` |
| CLI | `https://github.com/CodyBontecou/healthmd-cli.git` | `0905f1278644d2b17d1827d5af0f3fa34e7401a8` | `ae48b1484afeafad3dfa38e16d718b5681bb02b2` | `apps/cli` | Filtered default-branch history |
| Android | `https://github.com/CodyBontecou/health-md-android.git` | `95e7716809296ff29331a0f1d706dc7948c0d1e3` | `fd1da0454ce054ec4db896b6e2490c805e4fbdbb` | `apps/android` | Filtered default-branch history |
| Wake Worker | Local `healthmd-wake` Git repository (no remote configured) | `806b9ee3b62ecbdee8a1496a357ff8cec56c7a77` | Unchanged | `apps/wake` | Unsquashed subtree merge preserving all four source commits |
| Website | `https://github.com/CodyBontecou/obsidianhealth` | `7eb4a5038d1131b7fa110865448bdb6f3c467ecb` | `e133aae47a7c7d617b4ee2ad6cdc18db0fed394d` | `apps/website` | Filtered default-branch history |
| Obsidian plugin | `https://github.com/CodyBontecou/health-md-visualizations.git` | External | Not imported | Not imported | Remains an external integration |

The four 2026-07-24 source worktrees were clean and synchronized with `origin/main` when recorded.
The wake worktree was clean but had no remote; after its unsquashed import, this monorepo is the
canonical remote authority for those original commit hashes and future Worker source.

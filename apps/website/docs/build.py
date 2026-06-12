#!/usr/bin/env python3
"""Generate per-feature documentation pages from pages.py.

Each entry in pages.PAGES is an object describing a single feature page:
  slug, title, eyebrow, lead, body (HTML string), related (list).

This script wraps that content in a shared shell (head, header, sidebar,
footer) and writes /docs/{slug}/index.html.

Run: python3 build.py
"""
from __future__ import annotations

import importlib.util
import sys
from pathlib import Path
from textwrap import dedent

ROOT = Path(__file__).resolve().parent

SIDEBAR_GROUPS = [
    ("Getting Started", [
        ("index", "Overview", "../"),
        ("onboarding", "Onboarding", "../onboarding/"),
        ("folder-vault", "Folder & Vault", "../folder-vault/"),
    ]),
    ("Core Features", [
        ("export", "Export", "../export/"),
        ("scheduling", "Scheduling", "../scheduling/"),
        ("sync", "Mac Sync", "../sync/"),
    ]),
    ("Customization", [
        ("metrics", "Health Metrics", "../metrics/"),
        ("data-reference", "Data Reference", "../data-reference/"),
        ("format", "Format", "../format/"),
        ("individual-tracking", "Individual Tracking", "../individual-tracking/"),
        ("daily-notes", "Daily Note Injection", "../daily-notes/"),
    ]),
    ("Integrations", [
        ("shortcuts", "Shortcuts", "../shortcuts/"),
        ("macos", "macOS App", "../macos/"),
    ]),
    ("Account", [
        ("paywall", "Unlock & Paywall", "../paywall/"),
    ]),
]


def render_sidebar(active_slug: str) -> str:
    active_label = "Browse"
    for _, items in SIDEBAR_GROUPS:
        for slug, label, _href in items:
            if slug == active_slug:
                active_label = label
                break
    parts = [
        '<aside class="sidebar" data-open="false">',
        '  <button class="sidebar-toggle" type="button" aria-expanded="false" aria-controls="sidebar-nav">',
        '    <span class="sidebar-toggle-label">Menu<span class="sidebar-toggle-current">'
        f'{active_label}</span></span>',
        '    <span class="sidebar-toggle-chevron" aria-hidden="true">▾</span>',
        '  </button>',
        '  <div class="sidebar-nav" id="sidebar-nav">',
    ]
    for heading, items in SIDEBAR_GROUPS:
        parts.append(f"    <h4>{heading}</h4>")
        parts.append("    <ul>")
        for slug, label, href in items:
            cls = ' class="active"' if slug == active_slug else ""
            parts.append(f'      <li><a href="{href}" data-page="{slug}"{cls}>{label}</a></li>')
        parts.append("    </ul>")
    parts.append("  </div>")
    parts.append("</aside>")
    return "\n    ".join(parts)


PAGE_TEMPLATE = dedent("""\
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>{title} — health.md Docs</title>
      <link rel="icon" href="../../favicon.ico" sizes="any">
      <link rel="apple-touch-icon" sizes="180x180" href="../../assets/app-icon/icon_180x180.png">
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Mono:wght@400;500;600;700&family=IBM+Plex+Sans:wght@400;500;600;700&family=IBM+Plex+Serif:wght@500;600;700&display=swap" rel="stylesheet">
      <script src="../../assets/theme.js"></script>
      <link rel="stylesheet" href="../styles.css">
      <link rel="stylesheet" href="../../assets/theme-icons.css">
    </head>
    <body data-page="{slug}">
      <header class="docs-header">
        <div class="container docs-header-inner">
          <a class="brand" href="../../index.html">
            <img src="../../assets/app-icon/icon_80x80.png" alt="health.md icon">
            <strong>health.md</strong>
          </a>
          <div class="header-actions">
            <nav class="header-links">
              <a href="../../index.html">Home</a>
              <a href="../" class="active">Docs</a>
              <a href="../../blog/">Blog</a>
              <a href="../../privacy-policy.html">Privacy</a>
              <a href="../../terms-of-service.html">Terms</a>
            </nav>
            <div class="theme-toggle" role="group" aria-label="Color theme">
              <button type="button" data-theme-option="system" aria-pressed="true">Auto</button>
              <button type="button" data-theme-option="light" aria-pressed="false">Light</button>
              <button type="button" data-theme-option="dark" aria-pressed="false">Dark</button>
            </div>
          </div>
        </div>
      </header>

      <main class="container docs-layout">
        {sidebar}

        <article class="docs-content">
          {hero_block}

          {body}

          {related_block}
        </article>
      </main>

      <footer class="docs-footer">
        <div class="container">
          <p>© 2026 health.md · Built by <a href="https://isolated.tech">isolated.tech</a></p>
        </div>
      </footer>

      <script>
        (function() {{
          var sidebar = document.querySelector('.sidebar');
          if (!sidebar) return;
          var toggle = sidebar.querySelector('.sidebar-toggle');
          if (!toggle) return;
          toggle.addEventListener('click', function() {{
            var open = sidebar.getAttribute('data-open') === 'true';
            sidebar.setAttribute('data-open', open ? 'false' : 'true');
            toggle.setAttribute('aria-expanded', open ? 'false' : 'true');
          }});
        }})();
      </script>
    </body>
    </html>
""")


def render_hero(page) -> str:
    eyebrow = page["eyebrow"]
    title = page["title"]
    lead = page["lead"]
    hero_shot = page.get("hero_shot")
    text_block = (
        f'<div class="docs-hero-text">\n'
        f'      <span class="docs-eyebrow">{eyebrow}</span>\n'
        f'      <h1>{title}</h1>\n'
        f'      <p class="lead">{lead}</p>\n'
        f'    </div>'
    )
    if not hero_shot:
        return f'<div class="docs-hero docs-hero--no-shot">\n    {text_block}\n  </div>'
    raw = hero_shot["raw"]
    caption = hero_shot.get("caption", "")
    cap_html = f'<figcaption>{caption}</figcaption>' if caption else ""
    shot_block = (
        f'<figure class="docs-hero-shot">\n'
        f'      <img src="../../assets/docs/raw/{raw}" alt="{caption or raw}" loading="lazy">\n'
        f'      {cap_html}\n'
        f'    </figure>'
    )
    return f'<div class="docs-hero">\n    {text_block}\n    {shot_block}\n  </div>'


def render_related(items) -> str:
    if not items:
        return ""
    cards = []
    for label, href, desc in items:
        cards.append(
            f'<a href="{href}"><span>{label}</span>{desc}</a>'
        )
    return (
        '<h2>Related</h2>\n'
        '<div class="related">\n  '
        + "\n  ".join(cards)
        + "\n</div>"
    )


def load_pages():
    spec = importlib.util.spec_from_file_location("pages", ROOT / "pages.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod.PAGES


def main() -> int:
    pages = load_pages()
    for page in pages:
        slug = page["slug"]
        out_dir = ROOT / slug
        out_dir.mkdir(parents=True, exist_ok=True)
        out_file = out_dir / "index.html"
        html = PAGE_TEMPLATE.format(
            title=page["title"],
            slug=slug,
            sidebar=render_sidebar(slug),
            hero_block=render_hero(page),
            body=page["body"],
            related_block=render_related(page.get("related", [])),
        )
        out_file.write_text(html)
        print(f"  wrote {out_file.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

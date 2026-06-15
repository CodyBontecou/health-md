#!/usr/bin/env python3
"""Generate the Starlight Data Reference page from the Swift source of truth."""
from __future__ import annotations

import html
import re
from collections import OrderedDict
from pathlib import Path
from textwrap import dedent

DOCS_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = Path(__file__).resolve().parents[3]
APP_ROOT = REPO_ROOT / "app"
METRICS_FILE = APP_ROOT / "HealthMd" / "Shared" / "Models" / "HealthMetrics.swift"
MAPPING_FILE = APP_ROOT / "HealthMd" / "Shared" / "Export" / "HealthMetricsDictionary.swift"
OUT_FILE = DOCS_ROOT / "src" / "content" / "docs" / "data-reference.md"


def metric_reference_body() -> str:
    """Build the data reference page from the Swift metric source of truth."""
    metrics_source = METRICS_FILE.read_text()
    mapping_source = MAPPING_FILE.read_text()

    category_labels = OrderedDict(
        re.findall(r"case\s+(\w+)\s+=\s+\"([^\"]+)\"", metrics_source)
    )

    metric_pattern = re.compile(
        r"HealthMetricDefinition\("
        r"id: \"([^\"]+)\",\s*"
        r"name: \"([^\"]+)\",\s*"
        r"category: \.(\w+),\s*"
        r"unit: \"([^\"]*)\",\s*"
        r"healthKitIdentifier: (nil|\"[^\"]+\"),\s*"
        r"metricType: \.(\w+),\s*"
        r"aggregation: \.(\w+)"
    )
    metrics = [
        {
            "id": match.group(1),
            "name": match.group(2),
            "category": match.group(3),
            "unit": match.group(4) or "-",
            "healthkit": match.group(5).strip('"') if match.group(5) != "nil" else "-",
            "type": match.group(6),
            "aggregation": match.group(7),
        }
        for match in metric_pattern.finditer(metrics_source)
    ]

    mapping_block_match = re.search(
        r"metricIdToFrontmatterKeys:\s*\[String:\s*\[String\]\]\s*=\s*\[(.*?)\n\s*\]\n\n\s*static let allKnownFrontmatterKeys",
        mapping_source,
        re.S,
    )
    mapping: dict[str, list[str]] = {}
    if mapping_block_match:
        for metric_id, key_block in re.findall(r"\"([^\"]+)\"\s*:\s*\[(.*?)\]", mapping_block_match.group(1), re.S):
            mapping[metric_id] = re.findall(r"\"([^\"]+)\"", key_block)

    grouped = OrderedDict((key, []) for key in category_labels)
    for metric in metrics:
        grouped.setdefault(metric["category"], []).append(metric)

    total_metrics = len(metrics)
    total_categories = len([items for items in grouped.values() if items])
    total_keys = len({key for keys in mapping.values() for key in keys})

    category_rows = []
    for category_key, items in grouped.items():
        if not items:
            continue
        category_rows.append(
            "<tr>"
            f"<td>{html.escape(category_labels.get(category_key, category_key))}</td>"
            f"<td>{len(items)}</td>"
            f"<td>{html.escape(', '.join(metric['id'] for metric in items[:5]))}{'...' if len(items) > 5 else ''}</td>"
            "</tr>"
        )

    category_sections = []
    for category_key, items in grouped.items():
        if not items:
            continue
        rows = []
        for metric in items:
            keys = mapping.get(metric["id"], [])
            rows.append(
                "<tr>"
                f"<td><strong>{html.escape(metric['name'])}</strong><code>{html.escape(metric['id'])}</code></td>"
                f"<td>{html.escape(metric['unit'])}</td>"
                f"<td>{html.escape(metric['aggregation'])}</td>"
                f"<td>{html.escape(metric['type'])}</td>"
                f"<td>{html.escape(', '.join(keys) if keys else '-')}</td>"
                f"<td><code>{html.escape(metric['healthkit'])}</code></td>"
                "</tr>"
            )
        category_sections.append(
            dedent(f"""
                <details class="metric-group">
                  <summary><span>{html.escape(category_labels.get(category_key, category_key))}</span><strong>{len(items)} metrics</strong></summary>
                  <div class="table-wrap">
                    <table class="data-table">
                      <thead>
                        <tr>
                          <th>Data point</th>
                          <th>Unit</th>
                          <th>Aggregation</th>
                          <th>Type</th>
                          <th>Frontmatter / Bases keys</th>
                          <th>HealthKit identifier</th>
                        </tr>
                      </thead>
                      <tbody>
                        {''.join(rows)}
                      </tbody>
                    </table>
                  </div>
                </details>
            """)
        )

    return dedent(f"""
        ## Current coverage

        <div class="reference-stats">
          <div><strong>{total_metrics}</strong><span>documented metrics</span></div>
          <div><strong>{total_categories}</strong><span>HealthKit categories</span></div>
          <div><strong>{total_keys}</strong><span>canonical frontmatter keys</span></div>
          <div><strong>4</strong><span>daily export formats</span></div>
        </div>

        <p>Metric rows below are generated from <code>HealthMetrics.swift</code> and <code>HealthMetricsDictionary.swift</code>. The metric ID is the app's stable selector ID. Frontmatter keys are the canonical snake_case keys used by Markdown frontmatter, Obsidian Bases, Daily Note Injection, and custom key mapping.</p>

        <div class="callout">
          <strong>Schema v3 data dictionary.</strong>
          <p style="margin-top:6px;">Every export writes <code>_healthmd_data_dictionary.json</code> next to your daily files. It maps each exported key to its canonical key, unit, HealthKit identifier, daily aggregation rule, and weekly/monthly/yearly roll-up rule so scripts and AI assistants do not have to guess how to interpret a field.</p>
        </div>

        ## Export structures

        <div class="options">
          <div class="option"><strong>Markdown</strong><p>One <code>.md</code> file per exported day. It starts with YAML frontmatter when metadata is enabled, then renders a human-readable <code># Health Data - {{{{date}}}}</code> body with category sections and optional workout tables.</p></div>
          <div class="option"><strong>Obsidian Bases</strong><p>One <code>.md</code> file per day containing YAML/frontmatter-first data. It uses the same canonical fields as Markdown frontmatter and can include nested <code>workout_details</code> for database views.</p></div>
          <div class="option"><strong>JSON</strong><p>One <code>.json</code> file per day. Top-level keys include <code>schema</code>, <code>schema_version</code>, <code>date</code>, <code>type</code>, <code>unit_system</code>, and a per-field <code>units</code> map, followed by category objects such as <code>sleep</code>, <code>activity</code>, <code>heart</code>, <code>vitals</code>, <code>workouts</code>, and other enabled categories.</p></div>
          <div class="option"><strong>CSV</strong><p>One <code>.csv</code> file per day. The header is <code>Date,Category,Metric,Value,Unit,Timestamp</code>. Daily aggregate rows leave <code>Timestamp</code> empty; timestamped sample rows include an ISO timestamp.</p></div>
        </div>

        ## Data dictionary and roll-up rules

        <p>The generated dictionary is a JSON array. Each entry describes one exported frontmatter-compatible field for the current settings. If you rename <code>active_calories</code> to <code>activeEnergyKcal</code>, <code>key</code> is the final exported property and <code>canonicalKey</code> remains the stable Health.md identifier.</p>
        <div class="schema-grid">
          <pre><code>{{
  "key": "active_calories",
  "canonicalKey": "active_calories",
  "metricId": "active_energy",
  "displayName": "Active Energy",
  "category": "Activity",
  "unit": "kcal",
  "healthKitIdentifier": "HKQuantityTypeIdentifierActiveEnergyBurned",
  "metricType": "quantity",
  "dailyAggregation": "sum",
  "healthKitAggregation": "cumulative",
  "rollup": {{
    "primary": "sum",
    "statistics": ["sum", "daily_average", "minimum_daily_value", "maximum_daily_value", "days_counted"],
    "periods": ["weekly", "monthly", "yearly"],
    "preferredSource": "daily_frontmatter",
    "nullHandling": "ignore_missing_days_and_report_days_counted"
  }},
  "schemaVersion": 3
}}</code></pre>
          <pre><code>{{
  "canonicalKey": "workout_avg_heart_rate",
  "dailyAggregation": "weighted_average",
  "rollup": {{
    "primary": "weighted_average",
    "preferredSource": "workout_details_when_available",
    "weightedBy": "duration",
    "statistics": ["weighted_average", "minimum_daily_value", "maximum_daily_value", "latest", "days_counted"]
  }}
}}</code></pre>
        </div>
        <div class="options">
          <div class="option"><strong>Use <code>unit</code></strong><p>Do not infer units from the key name. Schema v3 dictionary entries state the exact structured unit for every exported key.</p></div>
          <div class="option"><strong>Use <code>dailyAggregation</code></strong><p>This tells you whether the daily value is a sum, average, minimum, maximum, latest value, list, category, or duration-weighted value.</p></div>
          <div class="option"><strong>Use <code>rollup</code></strong><p>Weekly, monthly, and yearly summary builders should use <code>rollup.primary</code> for the headline statistic and preserve the additional <code>rollup.statistics</code>.</p></div>
          <div class="option"><strong>Report provenance</strong><p>Missing days are ignored, not treated as zero. Summary files should include <code>days_counted</code> or an equivalent field.</p></div>
        </div>

        ## Daily file examples

        <div class="schema-grid">
          <pre><code>---
schema: healthmd.health_data
schema_version: 3
date: 2026-06-12
type: health-data
units:
  steps: count
  sleep_total_hours: hours
steps: 12642
sleep_total_hours: 7.31
workout_count: 1
---

# Health Data - 2026-06-12

## Activity
- Steps: 12642</code></pre>
          <pre><code>{{
  "schema": "healthmd.health_data",
  "schema_version": 3,
  "date": "2026-06-12",
  "type": "health-data",
  "unit_system": "metric",
  "units": {{
    "steps": "count",
    "active_calories": "kcal"
  }},
  "activity": {{
    "steps": 12642,
    "activeCalories": 604
  }},
  "sleep": {{
    "totalDuration": 26316,
    "totalDurationFormatted": "7h 18m"
  }}
}}</code></pre>
          <pre><code>Date,Category,Metric,Value,Unit,Timestamp
2026-06-12,Metadata,schema,healthmd.health_data,,
2026-06-12,Metadata,schema_version,3,,
2026-06-12,Activity,Steps,12642,count,
2026-06-12,Heart,Heart Rate Sample,72,bpm,2026-06-12T14:20:00Z</code></pre>
          <pre><code>---
schema: healthmd.health_data
schema_version: 3
date: 2026-06-12
type: health-data
steps: 12642
workout_details:
  - index: 1
    type: workout
    metric: workouts
---</code></pre>
        </div>

        ## Individual entry files

        <p>Individual Entry Tracking creates additional Markdown files under <code>entries/</code> by default. The generic schema is YAML frontmatter only. Workout entries add a readable body with summary, heart-rate zones, laps, splits, and sample counts when that data is available.</p>
        <pre><code>---
date: 2026-06-12
time: "07:30"
datetime: 2026-06-12T07:30:00Z
type: workout
metric: workouts
source: Health.md
duration_sec: 2700
distance_km: 6.20
hr_avg: 142
---</code></pre>

        ## Category summary

        <div class="table-wrap">
          <table class="data-table compact">
            <thead>
              <tr><th>Category</th><th>Metrics</th><th>First metric IDs</th></tr>
            </thead>
            <tbody>
              {''.join(category_rows)}
            </tbody>
          </table>
        </div>

        ## All data points

        {''.join(category_sections)}
    """)


def convert_pre_code_to_fences(body: str) -> str:
    """Convert generated raw HTML code blocks to Markdown fences."""

    body = re.sub(
        r"\n\s*<div class=\"schema-grid\">\s*((?:(?:<pre><code>.*?</code></pre>)\s*)+)</div>",
        lambda match: "\n" + match.group(1).strip() + "\n",
        body,
        flags=re.S,
    )

    def repl(match: re.Match[str]) -> str:
        code = match.group(1).strip("\n")
        stripped = code.lstrip()
        if stripped.startswith("{"):
            language = "json"
        elif stripped.startswith("Date,"):
            language = "csv"
        elif "# Health Data" in code:
            language = "markdown"
        elif stripped.startswith("---"):
            language = "yaml"
        else:
            language = "text"
        return f"\n```{language}\n{code}\n```\n"

    return re.sub(r"<pre><code>(.*?)</code></pre>", repl, body, flags=re.S)


def normalize_markdown_html(body: str) -> str:
    """Remove generator indentation that Markdown would treat as code blocks."""
    lines = body.strip().splitlines()
    out: list[str] = []
    in_pre = False
    for line in lines:
        if not in_pre:
            line = re.sub(r"^\s+(?=(<|#{1,6}\s|<!--))", "", line)
        out.append(line.rstrip())
        if "<pre" in line:
            in_pre = True
        if "</pre>" in line:
            in_pre = False
    return "\n".join(out).strip()


def main() -> int:
    frontmatter = dedent("""\
        ---
        title: Data Reference
        description: Every metric, frontmatter key, unit, aggregation, and export schema generated from the Health.md source of truth.
        ---

        <!-- Generated by docs-src/scripts/generate-data-reference.py. Do not hand-edit generated tables. -->

    """)
    body = normalize_markdown_html(convert_pre_code_to_fences(metric_reference_body()))
    OUT_FILE.write_text(frontmatter + body + "\n")
    print(f"wrote {OUT_FILE.relative_to(DOCS_ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

---
title: "Apple Watch Respiratory Rate: Where to Find It and How to Export It"
description: "Where Apple Watch respiratory rate shows up in Vitals and Health, why it can be blank, and how to keep the history as export.xml or as daily CSV, JSON or Markdown."
lead: "Apple Watch records respiratory rate while you sleep. Here is what Apple says about it, where to see it, why it may be missing, and how to keep your own history as a file."
date: "2026-11-27"
updated: "2026-11-27"
category: "Export guide"
platform: apple
related:
  - export-apple-health-sleep-data
  - apple-health-xml-export
  - export-apple-health-hrv
draft: false
verified: "2026-11-27"
verified_by: "Claude (agent)"
verified_method: traced
tags:
  - apple-health
  - apple-watch
  - vitals
  - export
---

**Apple Watch measures respiratory rate (breaths per minute) while you sleep, if Sleep tracking is on.** You see it in the Vitals app on the watch and in Health on iPhone. To keep the history as a file, use Health's **Export All Health Data** (a free `export.zip` containing `export.xml`) or Health.md (daily average, minimum and maximum as CSV, JSON or Markdown). Apple says Vitals measurements are not intended for medical use, and this page does not interpret your numbers or give a "normal" range. A clinician is the right person to do that.

## What Apple Watch measures and when

Apple's [overnight vitals article](https://support.apple.com/en-us/120142) lists respiratory rate as an overnight metric in the Vitals app, and says Sleep must be set up, with Track Sleep with Apple Watch and Sleep Focus turned on. It lists an iPhone with the latest version of iOS and an Apple Watch with the latest version of watchOS. Apple's [sleep tracking article](https://support.apple.com/en-us/108906) says you must turn on Track Sleep with Apple Watch and wear the watch for at least 1 hour each night, and that Respiratory Rate is not available for users under 13 years old.

The Vitals app builds a typical range for each metric. Apple's overnight vitals article says you need to wear your watch to bed for 7 days to establish it. Apple's [Vitals guide](https://support.apple.com/guide/watch/apd15aa7ed96) says "Not all features are available in all areas and on all models," so check Apple's current pages for your watch and region.

Apple's disclaimer in the overnight vitals article reads: "Vitals app measurements are not intended for medical use."

Related Vitals metrics Apple lists alongside respiratory rate are heart rate, wrist temperature, blood oxygen and sleep duration (on some newer models, heart rate variability instead of sleep duration). Availability varies by model and region, so follow Apple's pages for those.

## Where to see it

- **Apple Watch:** open the **Vitals** app, turn the Digital Crown to a metric and tap it to see more (Apple Watch User Guide).
- **iPhone, Vitals:** open **Health**, tap **Browse**, then **Vitals**, then tap a metric.
- **iPhone, Sleep:** in Health's Sleep section, **Show More Sleep Data**, then **Comparisons**, shows Heart Rate and Respiratory Rate in relation to your time asleep.

Apple's regional pages and different iOS or watchOS versions word these paths slightly differently, so follow what your own device shows.

## Why respiratory rate is blank or not updating

Apple's pages support these causes:

- **Sleep tracking or Sleep setup is off.** Apple says Sleep must be set up, with Track Sleep with Apple Watch on.
- **You did not wear the watch to sleep.** Apple says to wear it for at least 1 hour each night.
- **The fit is too loose.** Apple says: "If your watch is too loose, the sensors might not capture accurate readings."
- **The watch or software is not supported.** Apple lists the latest watchOS and says not all features are available in all areas and on all models.
- **Vitals is still building your typical range.** Apple says this takes 7 days of wearing the watch to bed.
- **Respiratory Rate was turned off.** Apple documents a Respiratory Rate switch in Privacy settings on the watch and in the Apple Watch app on iPhone.

Anything beyond these (for example other iPhone settings) is a suggestion to check, not something Apple's pages state.

## Export option 1: Apple's Export All Health Data

1. Open **Health**, tap your picture or initials, then choose **Export All Health Data**. Apple documents this in its [Health sharing guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios).
2. Save or send the resulting `export.zip`. Inside is `export.xml`.
3. Look for records of type `HKQuantityTypeIdentifierRespiratoryRate`. Apple's [HealthKit page](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/respiratoryrate) documents the type; Health.md's catalog lists its unit as breaths/min. Check the unit string in your own file before you chart it.

This is free and complete, but it is one large archive of every record, not a table of daily values. See [how to open export.xml](/blog/apple-health-xml-export/).

## Export option 2: Health.md daily files

Health.md for iPhone writes daily respiratory rate values as CSV, JSON or Markdown to a folder you choose. From the generated [metric catalog](/docs/reference/generated/core/metric-catalog/), row `respiratory_rate`: source unit breaths/min, HealthKit identifier `HKQuantityTypeIdentifierRespiratoryRate`, and Default "yes", so it is part of the default selection.

| Frontmatter key | Meaning |
| --- | --- |
| `respiratory_rate` | daily average |
| `respiratory_rate_avg` | daily average |
| `respiratory_rate_min` | daily minimum |
| `respiratory_rate_max` | daily maximum |

In daily JSON the fields are under `vitals`: `respiratoryRate`, `respiratoryRateAvg`, `respiratoryRateMin`, `respiratoryRateMax` and `respiratoryRateSamples` (see the [daily JSON field inventory](/docs/reference/generated/core/daily-json-fields/)). In CSV, the Vitals category has the rows "Respiratory Rate Avg", "Respiratory Rate Min", "Respiratory Rate Max" and "Respiratory Rate Sample" (see the [CSV row contracts](/docs/reference/generated/core/csv-row-contracts/)).

A fictional Markdown frontmatter excerpt (not a real person's data; the values are made up):

```yaml
respiratory_rate_avg: 14.2
respiratory_rate_min: 12.0
respiratory_rate_max: 17.5
```

A listed key does not guarantee a value. The catalog says a listed key does not guarantee a summary value, because summaries need qualifying data. If Apple Health has no respiratory rate for a day, expect nothing for that day, not zero.

## Which day a night's reading lands on

Overnight data crosses midnight, so see [why last night's sleep is in yesterday's note](/blog/why-sleep-is-in-yesterdays-note/). That post describes the noon-to-noon journal window for sleep summaries. This page does not state a separate attribution rule for respiratory rate, so check a day you know in a preview before relying on it.

## Common questions

### Does Apple Watch measure respiratory rate during the day?

Apple's pages describe respiratory rate as an overnight metric, measured as you sleep. Apple's Vitals guide says the app has a daytime view, but the pages we read describe daytime vitals as heart rate and heart rate variability on some newer models, not respiratory rate.

### Can I export respiratory rate to Excel?

Yes. Export daily CSV files with Health.md, or convert Apple's `export.xml`. See [Apple Health to Excel](/blog/apple-health-to-excel/).

### Where does overnight heart rate variability fit?

It is a separate metric. See [exporting HRV](/blog/export-apple-health-hrv/) and the [sleep data guide](/blog/export-apple-health-sleep-data/).

## Get daily files

Health.md writes your daily respiratory rate to files in a folder you choose on your iPhone, using the local folder export workflow. The separate Health.md Cloud pilot is opt-in, single-owner and not generally available. See also [Apple Health export](/apple-health-export/).

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

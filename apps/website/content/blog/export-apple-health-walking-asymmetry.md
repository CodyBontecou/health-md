---
title: "Walking Asymmetry on iPhone: What It Means and How to Export It"
description: "What iPhone's walking asymmetry percentage measures, why it can be blank, and how to keep daily history as CSV, JSON or Markdown, or as Apple's export.xml."
lead: "Walking asymmetry is a percentage Apple records when your iPhone is carried near your waist. Here is what Apple says it measures, why it may be empty, and how to keep the history as a file."
date: "2026-11-23"
updated: "2026-11-23"
category: "Export guide"
related:
  - export-apple-health-steps-data
  - apple-health-xml-export
  - export-apple-health-data-pdf
draft: false
verified: "2026-11-23"
verified_by: "Claude (agent)"
verified_method: traced
platform: apple
tags:
  - apple-health
  - mobility
  - export
---

**Walking asymmetry is the percentage of your steps in which one foot moves at a different speed than the other.** Apple's HealthKit documentation describes it as the percent of time that steps with one foot are faster or slower than the other, recorded on iPhone 8 or later when you carry the phone near your waist and walk steadily on flat ground. To see it, open **Health → Browse → Mobility** and look for **Walking Asymmetry** (you may need to scroll). To keep the history as a file, use the Health app's **Export All Health Data** (a free `export.zip` with everything in `export.xml`) or Health.md (daily values as CSV, JSON or Markdown). Apple's HealthKit page for walking asymmetry gives no "normal" figure, and this page does not either. A clinician is the right person to interpret your numbers.

## What walking asymmetry measures

Apple's [HealthKit documentation](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingasymmetrypercentage) defines the type as "the percentage of steps in which one foot moves at a different speed than the other when walking on flat ground." Its description adds that the system records the samples automatically on iPhone 8 or later, the phone must be carried near the waist (for example in a pocket) and the user must walk steadily on flat ground, and that iPhone does not record them if the wheelchair status is on. Apple documents 10 to 30 samples on a typical day.

A lower percentage means fewer of your measured steps were uneven. Health.md only passes through the value Apple records. It does not judge whether it is good or bad, and Apple's HealthKit page gives no reference range for it. The Health app shows your own trend, which is the most useful comparison when you are following recovery over weeks.

## The related mobility metrics

These are the metrics Health.md writes alongside walking asymmetry. The definitions are Apple's HealthKit wording, shortened.

| Metric | Apple's description | Unit in Health.md files |
| --- | --- | --- |
| Walking speed | The user's average speed when walking steadily over flat ground. | m/s in CSV and JSON; km/h in Markdown (metric setting) |
| Step length | The average length of the user's step when walking steadily over flat ground. Apple notes the height value must be up to date for accuracy. | meters in CSV; cm in Markdown |
| Double support time | The percentage of time when both feet touch the ground while walking steadily over flat ground. Apple states a typical walk falls between 20% and 40%, and that it varies with walking speed and terrain. | percent |
| Walking asymmetry | The percentage of steps in which one foot moves at a different speed than the other. | percent |
| Walking steadiness | A score for the steadiness of your gait, shown as OK, Low or Very Low in the Health app. | percent |
| Stair ascent / descent speed | How fast you walk up or down a flight of stairs. | m/s in CSV and JSON |

Apple documents the stair speeds as recorded on Apple Watch Series 5 or later, for a 10-foot (3-meter) flight of steps while wearing the watch, which differs from the four iPhone metrics above. See the HealthKit pages for [walking speed](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingspeed), [step length](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingsteplength), [double support](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/walkingdoublesupportpercentage), [stair ascent speed](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stairascentspeed) and [stair descent speed](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/stairdescentspeed).

**Walking steadiness** is a separate measure. Apple's [walking steadiness article](https://support.apple.com/en-us/102504) says Health "uses custom algorithms that assess your balance, strength, and gait," and names three levels: OK, Low and Very Low. It says you can receive a notification if your steadiness becomes low or stays low, and that it needs iPhone 8 or later carried in a pocket or holster near your waist. The HealthKit documentation says the system creates a walking steadiness sample every 7 days, and longer if there is not enough mobility data.

## Why walking asymmetry is blank or "not working"

Apple's documentation supports these causes:

- **The phone was not carried at the waist.** The sample is only recorded when the phone is near your waist, such as in a pocket. A bag, hand or armband is not what Apple describes.
- **Walking was not steady or not on flat ground.** Apple says you must walk steadily on flat ground. Apple does not describe other walking as being measured.
- **The device is not supported.** Apple documents iPhone 8 or later.
- **Wheelchair status is on.** Apple says iPhone does not record the sample in that case.
- **Height is out of date (related metrics).** Apple says an up-to-date height is needed for accuracy of walking speed and step length, and that you must set your height for walking steadiness. It does not say this for asymmetry.
- **Motion & Fitness is off.** Apple's pages above do not state this setting, so this page does not claim it. If the whole Mobility section is empty, check **Settings → Privacy & Security → Motion & Fitness** and the Health access list for your device.

**Does Apple Watch measure walking asymmetry?** Apple documents walking asymmetry, double support, step length and walking speed as iPhone mobility metrics: the system records them on iPhone 8 or later, carried near the waist. The pages we checked do not describe an Apple Watch recording them, so a watch worn without the phone at your waist is not a documented source. Apple documents Apple Watch Series 5 or later for stair speeds only.

## See the trend in the Health app

Open **Health**, tap **Browse**, then **Mobility**, and tap the metric. For walking steadiness, Apple's [iPhone User Guide](https://support.apple.com/guide/iphone/monitor-your-walking-steadiness-iphff1bf03ed/ios) lists the same route (Browse, Mobility, Walking Steadiness, Show More Walking Steadiness Data) and says you can share a steadiness notification with someone close to you. Check the screen on your own iPhone for the chart ranges and data-list options your iOS version offers.

## Export the history: Apple's own route first

1. Open **Health → Summary**, tap your picture or initials, then choose **Export All Health Data**. Apple documents this in its [Health sharing guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios).
2. Save or send the resulting `export.zip`. Inside is `export.xml`.
3. Look for records whose type is `HKQuantityTypeIdentifierWalkingAsymmetryPercentage`. The matching identifiers for the other metrics are `HKQuantityTypeIdentifierWalkingDoubleSupportPercentage`, `HKQuantityTypeIdentifierWalkingStepLength`, `HKQuantityTypeIdentifierWalkingSpeed`, `HKQuantityTypeIdentifierAppleWalkingSteadiness`, `HKQuantityTypeIdentifierStairAscentSpeed` and `HKQuantityTypeIdentifierStairDescentSpeed`.

This is free and complete, but it is one large archive with every record, not a table of daily values. See [how to open export.xml](/blog/apple-health-xml-export/) and [Apple Health to Excel](/blog/apple-health-to-excel/) for turning it into rows.

## Export daily values with Health.md

Health.md for iPhone writes one value per day for these mobility metrics, as CSV, JSON or Markdown, to a folder you choose. The names and aggregation come from the generated [metric catalog](/docs/reference/generated/core/metric-catalog/):

| Markdown/frontmatter field | Aggregation | Unit written |
| --- | --- | --- |
| `walking_asymmetry_percent` | daily average | percent |
| `double_support_percent` | daily average | percent |
| `step_length_cm` | daily average | cm |
| `walking_speed` | daily average | m/s |
| `walking_steadiness_percent` | daily latest | percent |
| `stair_ascent_speed`, `stair_descent_speed` | daily average | m/s |

The Mobility metrics are enabled by default and each is written only when Apple Health has a value for that day. A missing row means no value was available, not zero. In JSON the nested `mobility` object stores the percentages as fractions (a fictional `0.015` is 1.5%), so check the units dictionary before charting.

Here is a **fictional** daily CSV excerpt, taken from Health.md's generated sample day (not a real person's data):

```csv
Date,Category,Metric,Value,Unit,Timestamp
2026-03-15,Mobility,Walking Speed,1.42,m/s
2026-03-15,Mobility,Walking Step Length,0.73,meters
2026-03-15,Mobility,Double Support Percentage,27.0,percent
2026-03-15,Mobility,Walking Asymmetry,1.5,percent
2026-03-15,Mobility,Stair Ascent Speed,0.62,m/s
2026-03-15,Mobility,Stair Descent Speed,0.71,m/s
2026-03-15,Mobility,Walking Steadiness,92.0,%
```

And the same fictional day in Markdown:

```markdown
## Mobility

- **Walking Speed:** 5.1 km/h
- **Step Length:** 73.0 cm
- **Double Support:** 27.0%
- **Walking Asymmetry:** 1.5%
- **Stair Ascent Speed:** 2.2 km/h
- **Stair Descent Speed:** 2.6 km/h
- **Walking Steadiness:** 92.0%
```

You can download the full [fictional sample CSV](/docs/reference/generated/core/summary-day.csv).

**What Health.md does not do:** it does not write per-step or per-bout samples in the daily summary, it does not interpret your numbers medically, and these metrics are not available on Android in Health.md today.

Want walking asymmetry and the other mobility metrics as one row per day? Health.md for iPhone writes them to CSV, JSON or Markdown in a folder you choose.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

## Use the history

- **Before and after:** export a few weeks before and after an injury, surgery or physiotherapy plan, and keep the files together. Compare like with like: the same metric, the same unit and the days that actually have a value.
- **Chart it:** import the daily CSV files into a spreadsheet using the [Excel walkthrough](/blog/apple-health-to-excel/), filtering `Category = Mobility` and `Metric = Walking Asymmetry`. Do not fill missing days with zero.
- **Notes:** write the values into daily notes with [Apple Health to Obsidian](/blog/export-apple-health-data-to-obsidian/).
- **With walking totals:** [steps](/blog/export-apple-health-steps-data/) export the same way.
- **For a clinician:** bring the CSV, or Health.md's [Clinician Report PDF](/blog/export-apple-health-data-pdf/), and let them interpret it. See [Apple Health to CSV](/apple-health-to-csv/) for the row format.

## Where the files go

Health.md writes files to a folder you choose on your device, using the local folder export workflow. Synced folders and anything you share follow their own providers' rules. The separate Health.md Cloud pilot is opt-in, single-owner and not generally available, and folder exports are not uploaded to it.

## Common questions

### What is a good walking asymmetry percentage?

Apple's HealthKit page for walking asymmetry gives no normal range, so this page does not either. Lower means fewer uneven steps. Use the trend in your Health app and ask a clinician what your numbers mean.

### Does Apple Watch measure walking asymmetry?

Apple documents it as recorded on iPhone 8 or later, carried near the waist. Apple Watch Series 5 or later is documented for stair speeds, not for walking asymmetry.

### Why is my walking asymmetry empty?

Check that you carry your iPhone near your waist, that you walk steadily on flat ground, that your iPhone is iPhone 8 or later and that wheelchair status is off. Apple documents only steady walking on flat ground as being measured.

### Can I export walking asymmetry to Excel?

Yes. Export daily CSV files with Health.md and open them in Excel, or convert Apple's `export.xml`. See [Apple Health to Excel](/blog/apple-health-to-excel/).

---
title: "Find workout distance in Apple Health export.xml"
description: "Where a workout's distance lives in Apple Health's export.xml: WorkoutStatistics in current exports and totalDistance in older ones. Includes a stdlib Python parser that writes one CSV row per workout."
lead: "Read the WorkoutStatistics child first, fall back to the legacy totalDistance attribute, and leave distance blank when neither exists. A tested Python script does this for a whole export."
date: "2026-11-19"
updated: "2026-11-19"
category: "Workflow guide"
platform: apple
related:
  - apple-health-xml-export
  - export-apple-health-workouts
  - apple-health-to-python
draft: false
verified: "2026-11-19"
verified_by: "Claude (agent)"
verified_method: mixed
tags:
  - apple-health
  - xml
  - workouts
  - python
---

**In a current Apple Health `export.xml`, a workout's distance is usually in a child `<WorkoutStatistics>` element inside `<Workout>`: its `type` starts with `HKQuantityTypeIdentifierDistance`, the value is in `sum` and the unit in `unit`. Older exports put it in the `totalDistance` and `totalDistanceUnit` attributes on `<Workout>` itself.** Check both, and read the distance type that matches the sport.

If neither is present, the workout has no recorded distance. That's common for strength training and other workouts that don't measure distance. Leave the value blank rather than writing 0.

Every XML excerpt, value and output row below is fictional.

## Where workouts live in export.zip

On iPhone, **Health → your picture or initials → Export All Health Data** creates the archive. Apple's [Health sharing guide](https://support.apple.com/guide/iphone/share-your-health-data-iph5ede58c3d/ios) documents the export. The [Apple Health XML export guide](/blog/apple-health-xml-export/) covers unzipping it on iPhone, Mac and Windows.

Inside the unzipped folder:

- **`export.xml`** holds the data, including one `<Workout>` element per workout. Workouts sit alongside millions of `<Record>` elements, so the file can be large.
- **`workout-routes/`** holds GPX files. A workout with a route links to one through a `<WorkoutRoute>` child, whose `<FileReference>` `path` points into `/workout-routes/`.

The file starts with an inline DTD, `<!DOCTYPE HealthData [ … ]>`, that declares every element and attribute. That DTD is the most reliable description of the format your copy uses. Read it before trusting any guide, including this one.

## Old and new Workout shapes

The [DTD from an export version 11 archive](https://github.com/AlekSi/applehealth/blob/main/healthkit11.dtd) allows only `MetadataEntry`, `WorkoutEvent` and `WorkoutRoute` inside `<Workout>`, so distance has to be an attribute. Here is a fictional 5.02 km run in that shape:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<HealthData locale="en_US">
 <ExportDate value="2026-03-20 09:00:00 -0700"/>
 <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="31.5" durationUnit="min" totalDistance="5.02" totalDistanceUnit="km" totalEnergyBurned="310" totalEnergyBurnedUnit="kcal" sourceName="Example Watch" creationDate="2026-03-15 07:32:10 -0700" startDate="2026-03-15 07:00:00 -0700" endDate="2026-03-15 07:31:30 -0700">
 </Workout>
</HealthData>
```

A [DTD copied from an export version 17 archive](https://github.com/gauthier-se/verve/blob/main/internal/synthexport/prolog.txt) adds `WorkoutStatistics`, `WorkoutActivity`, `WorkoutZoneGroup` and `Record` as `<Workout>` children. Each `WorkoutStatistics` has `type`, `startDate`, `endDate` and optional `average`, `minimum`, `maximum`, `sum` and `unit`. That DTD still declares `totalDistance`, but as optional. The project that published it [reports](https://github.com/gauthier-se/verve/issues/138) that in the real export it inspected, no workout had `totalDistance` and the totals were only in `WorkoutStatistics`.

Here is the same fictional run in the newer shape, plus a ride logged in miles and a strength workout with no distance:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<HealthData locale="en_US">
 <ExportDate value="2026-03-20 09:00:00 -0700"/>
 <Workout workoutActivityType="HKWorkoutActivityTypeRunning" duration="31.5" durationUnit="min" sourceName="Example Watch" creationDate="2026-03-15 07:32:10 -0700" startDate="2026-03-15 07:00:00 -0700" endDate="2026-03-15 07:31:30 -0700">
  <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" startDate="2026-03-15 07:00:00 -0700" endDate="2026-03-15 07:31:30 -0700" sum="310" unit="Cal"/>
  <WorkoutStatistics type="HKQuantityTypeIdentifierDistanceWalkingRunning" startDate="2026-03-15 07:00:00 -0700" endDate="2026-03-15 07:31:30 -0700" sum="5.02" unit="km"/>
  <WorkoutRoute sourceName="Example Watch" creationDate="2026-03-15 07:32:15 -0700" startDate="2026-03-15 07:00:00 -0700" endDate="2026-03-15 07:31:30 -0700">
   <FileReference path="/workout-routes/route_2026-03-15_7.31am.gpx"/>
  </WorkoutRoute>
 </Workout>
 <Workout workoutActivityType="HKWorkoutActivityTypeCycling" duration="48" durationUnit="min" sourceName="Example Watch" startDate="2026-03-16 18:10:00 -0700" endDate="2026-03-16 18:58:00 -0700">
  <WorkoutStatistics type="HKQuantityTypeIdentifierDistanceCycling" startDate="2026-03-16 18:10:00 -0700" endDate="2026-03-16 18:58:00 -0700" sum="12.4" unit="mi"/>
 </Workout>
 <Workout workoutActivityType="HKWorkoutActivityTypeTraditionalStrengthTraining" duration="40" durationUnit="min" sourceName="Example Watch" startDate="2026-03-17 12:00:00 -0700" endDate="2026-03-17 12:40:00 -0700">
  <WorkoutStatistics type="HKQuantityTypeIdentifierActiveEnergyBurned" startDate="2026-03-17 12:00:00 -0700" endDate="2026-03-17 12:40:00 -0700" sum="180" unit="Cal"/>
 </Workout>
</HealthData>
```

The change follows HealthKit itself. Apple's documentation marks [`HKWorkout.totalDistance`](https://developer.apple.com/documentation/healthkit/hkworkout/totaldistance) as deprecated and points to [`allStatistics`](https://developer.apple.com/documentation/healthkit/hkworkout/allstatistics) or [`statistics(for:)`](https://developer.apple.com/documentation/healthkit/hkworkout/statistics(for:)), which arrived in iOS 16 with [`HKWorkoutActivity`](https://developer.apple.com/documentation/healthkit/hkworkoutactivity).

## Pick the distance type for the sport

Each distance is its own HealthKit quantity type, so a `WorkoutStatistics` element names which kind of distance it is. Match it to the workout's `workoutActivityType`:

| Workout type (`HKWorkoutActivityType…`) | Distance statistic (`HKQuantityTypeIdentifier…`) |
| --- | --- |
| Running, Walking, Hiking | [`DistanceWalkingRunning`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancewalkingrunning) |
| Cycling | [`DistanceCycling`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancecycling) |
| Swimming | [`DistanceSwimming`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distanceswimming) |
| WheelchairWalkPace, WheelchairRunPace | [`DistanceWheelchair`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancewheelchair) |
| DownhillSkiing, Snowboarding | [`DistanceDownhillSnowSports`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancedownhillsnowsports) |
| Rowing | [`DistanceRowing`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancerowing) (iOS 18+) |
| PaddleSports | [`DistancePaddleSports`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancepaddlesports) (iOS 18+) |
| CrossCountrySkiing | [`DistanceCrossCountrySkiing`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distancecrosscountryskiing) (iOS 18+) |
| SkatingSports | [`DistanceSkatingSports`](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/distanceskatingsports) (iOS 18+) |

The pairings follow Apple's descriptions of each identifier. A workout usually has only one distance statistic, so the table matters most when it has several. A triathlon ([`swimBikeRun`](https://developer.apple.com/documentation/healthkit/hkworkoutactivitytype/swimbikerun)) is the obvious case.

## Python: stream every workout to CSV

This script uses only the Python standard library (3.9 or later). It reads `export.xml` line by line with [`XMLPullParser`](https://docs.python.org/3/library/xml.etree.elementtree.html#xml.etree.ElementTree.XMLPullParser), the feed-based form of `iterparse`. It clears each top-level element once it has been handled, so memory stays flat on a large export. In our test, a 452 MB fictional export with 2 million records and 60,000 workouts peaked at about 32 MB of memory.

For each workout, the script:

1. Uses the workout-level `WorkoutStatistics` distance that matches the sport. If there's only one distance statistic, it uses that one.
2. Falls back to the `totalDistance` and `totalDistanceUnit` attributes.
3. Leaves distance blank when neither exists, or when several distance types exist and none matches the sport.
4. Keeps the original value and unit, and adds `distance_km` for the units it knows.

It also skips the inline DTD and repairs one reported iOS 16 attribute bug. The gotchas below explain both.

Save it as `workout_distance.py`:

```python
#!/usr/bin/env python3
"""Write one CSV row per <Workout> in an Apple Health export.xml."""
import csv
import re
import sys
import xml.etree.ElementTree as ET

DISTANCE = "HKQuantityTypeIdentifierDistance"
# Preferred distance statistic per workout type (only used when a workout has several).
SPORT_DISTANCE = {
    "Running": "WalkingRunning", "Walking": "WalkingRunning", "Hiking": "WalkingRunning",
    "Cycling": "Cycling", "Swimming": "Swimming",
    "WheelchairWalkPace": "Wheelchair", "WheelchairRunPace": "Wheelchair",
    "DownhillSkiing": "DownhillSnowSports", "Snowboarding": "DownhillSnowSports",
    "Rowing": "Rowing", "PaddleSports": "PaddleSports",
    "CrossCountrySkiing": "CrossCountrySkiing", "SkatingSports": "SkatingSports",
}
TO_KM = {"km": 1.0, "m": 0.001, "mi": 1.609344, "yd": 0.0009144, "ft": 0.0003048}
# Early iOS 16 exports were reported to repeat startDate where endDate belongs.
REPEATED_START = re.compile(r'(startDate="[^"]*"\s+)startDate=')
COLUMNS = ["type", "start", "end", "duration", "duration_unit", "distance",
           "distance_unit", "distance_km", "distance_type", "distance_from",
           "activities", "source"]


def export_lines(path):
    """Yield export.xml lines without the inline DTD, which the parse doesn't need."""
    in_dtd = False
    with open(path, encoding="utf-8") as f:
        for line in f:
            if not in_dtd and line.lstrip().startswith("<!DOCTYPE"):
                in_dtd = "[" in line
                continue
            if in_dtd:
                in_dtd = not line.strip().startswith("]>")
                continue
            yield REPEATED_START.sub(r"\1endDate=", line)


def distance_of(workout):
    sport = workout.get("workoutActivityType", "").removeprefix("HKWorkoutActivityType")
    stats = {s.get("type"): s for s in workout.findall("WorkoutStatistics")
             if s.get("type", "").startswith(DISTANCE) and s.get("sum")}
    preferred = DISTANCE + SPORT_DISTANCE.get(sport, "")
    if preferred in stats:
        stat = stats[preferred]
    elif len(stats) == 1:
        stat = next(iter(stats.values()))
    elif stats:  # several distance types and none matches the sport: don't guess
        kinds = "+".join(sorted(k.removeprefix(DISTANCE) for k in stats))
        return "", "", DISTANCE + kinds, "ambiguous"
    elif workout.get("totalDistance"):
        return (workout.get("totalDistance"), workout.get("totalDistanceUnit", ""),
                "", "totalDistance")
    else:
        return "", "", "", ""
    return stat.get("sum"), stat.get("unit", ""), stat.get("type"), "WorkoutStatistics"


def row_for(workout):
    distance, unit, kind, origin = distance_of(workout)
    km = f"{float(distance) * TO_KM[unit]:.3f}" if distance and unit in TO_KM else ""
    return {
        "type": workout.get("workoutActivityType", "").removeprefix("HKWorkoutActivityType"),
        "start": workout.get("startDate"), "end": workout.get("endDate"),
        "duration": workout.get("duration", ""), "duration_unit": workout.get("durationUnit", ""),
        "distance": distance, "distance_unit": unit, "distance_km": km,
        "distance_type": kind.removeprefix(DISTANCE), "distance_from": origin,
        "activities": len(workout.findall("WorkoutActivity")),
        "source": workout.get("sourceName", ""),
    }


def main(path):
    out = csv.DictWriter(sys.stdout, fieldnames=COLUMNS, lineterminator="\n")
    out.writeheader()
    parser = ET.XMLPullParser(events=("start", "end"))
    root, depth = None, 0
    for line in export_lines(path):
        parser.feed(line)
        for event, elem in parser.read_events():
            if event == "start":
                depth += 1
                root = elem if root is None else root
                continue
            depth -= 1
            if depth == 1:  # a complete top-level Record, Workout, ...
                if elem.tag == "Workout":
                    out.writerow(row_for(elem))
                root.clear()  # drop finished elements so memory stays flat
    parser.close()


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "export.xml")
```

Run it from the unzipped folder and write the result to a new file:

```sh
python3 workout_distance.py export.xml > workouts.csv
```

Run on the older-shape excerpt, it prints:

```csv
type,start,end,duration,duration_unit,distance,distance_unit,distance_km,distance_type,distance_from,activities,source
Running,2026-03-15 07:00:00 -0700,2026-03-15 07:31:30 -0700,31.5,min,5.02,km,5.020,,totalDistance,0,Example Watch
```

Run on the newer-shape excerpt, it prints:

```csv
type,start,end,duration,duration_unit,distance,distance_unit,distance_km,distance_type,distance_from,activities,source
Running,2026-03-15 07:00:00 -0700,2026-03-15 07:31:30 -0700,31.5,min,5.02,km,5.020,WalkingRunning,WorkoutStatistics,0,Example Watch
Cycling,2026-03-16 18:10:00 -0700,2026-03-16 18:58:00 -0700,48,min,12.4,mi,19.956,Cycling,WorkoutStatistics,0,Example Watch
TraditionalStrengthTraining,2026-03-17 12:00:00 -0700,2026-03-17 12:40:00 -0700,40,min,,,,,,0,Example Watch
```

The run gives the same 5.02 km either way, and `distance_from` records which shape it came from. The ride keeps its original `12.4` `mi` and adds 19.956 km. The strength workout has empty distance fields, not `0`.

## Gotchas

### The DTD can stop a parser before it reaches your data

Users reported that exports made after updating to iOS 16 (export version 12) had a malformed DTD and repeated attributes, which made R, `xmllint` and browsers reject the file. In the [Apple Community thread](https://discussions.apple.com/thread/254202523), several users said a fresh export after iOS 16.2 worked again, while one user on iOS 16.4.1 still reported a DTD error. These are user reports, not an Apple statement.

The repeated attribute is described in a [Developer Forums report](https://developer.apple.com/forums/thread/714063): `WorkoutStatistics` lines carried `startDate` twice, with the second where `endDate` belongs. An Apple engineer asked for a Feedback report, and the thread records no fix.

Choosing a "non-validating" parser isn't enough on its own. Python's expat parser is [non-validating](https://docs.python.org/3/library/pyexpat.html), but in our test it still rejected a malformed DTD with `syntax error` and a repeated attribute with `duplicate attribute`. That's why the script drops the DTD, which isn't needed to read elements, and renames a repeated `startDate` to `endDate` on the same line. If you're working from an iOS 16 era export, check a few of the repaired rows against the Health app.

### Multi-activity workouts

HealthKit added `HKWorkoutActivity` in iOS 16, and the version 17 DTD lets a `<Workout>` contain several `<WorkoutActivity>` children, each with its own `WorkoutStatistics`. There, `WorkoutActivity` has `uuid`, `startDate`, `endDate`, `duration` and `durationUnit`, but no activity type.

The script reads only the workout's direct `WorkoutStatistics` children, the workout-level totals. Searching every descendant with `.iter()` would count each leg twice: once in the total and once in its activity. The `activities` column shows how many activity children a workout had. If a triathlon has swimming and cycling totals, `distance_from` says `ambiguous` and `distance_type` lists both, for example `Cycling+Swimming`. Add the legs yourself only if a combined number means something for your analysis.

### Units are per element

`unit` sits on each statistic, and `totalDistanceUnit` on each older workout, so one export can mix `km` and `mi`. Apple's [HKUnit string table](https://developer.apple.com/documentation/healthkit/hkunit/init(from:)-9qont) lists `m` (with SI prefixes such as `km`), `ft`, `yd` and `mi`. Never sum the `distance` column without its unit. The script leaves `distance_km` blank for any unit it doesn't know, so check for blank `distance_km` next to a non-blank `distance`.

### Missing distance is not zero

`sum` and `totalDistance` are optional in the DTD. Strength training, yoga and other workouts that don't measure distance have none, and a manually logged workout has one only if someone entered it. A blank cell keeps averages honest. A 0 would pull an "average workout distance" down for every session that never measured distance.

### Summing raw distance records double counts

You might try to rebuild a missing distance by adding up `<Record>` rows of type `DistanceWalkingRunning` between a workout's `startDate` and `endDate`. An iPhone and an Apple Watch can both record the same walk, and both sets of records appear in `export.xml`. The Health app [ranks overlapping sources by priority](https://support.apple.com/108779) instead of adding them, so a plain sum can be close to twice the real distance.

The version 17 DTD also notes that records appearing inside a `<Workout>` also appear as top-level records. Counting both copies doubles them again. If you use this fallback anyway, filter to one `sourceName`, use only top-level records, and label the result as an approximation.

Watch for duplicate workouts too. A run recorded on a watch and also synced from another app can appear as two `<Workout>` elements with different `sourceName` values.

## Routes and laps are different data

A distance total is one number, and it can't rebuild a path. Apple stores routes as [`HKWorkoutRoute`](https://developer.apple.com/documentation/healthkit/hkworkoutroute) location samples. In the archive, they're the GPX files under `workout-routes/`, linked from each `<WorkoutRoute>`'s `FileReference`.

For routes, laps, splits and session identity, read [how to export Apple Health workouts](/blog/export-apple-health-workouts/#section-routes-laps-and-detailed-records). Don't add lap distances to the workout total. For deeper analysis in pandas or notebooks, continue with [Apple Health to Python](/blog/apple-health-to-python/).

## Skip the XML: daily workout files with Health.md

If you'd rather not parse the archive at all, Health.md for iPhone reads the workouts you authorize in Apple Health and writes them to CSV, JSON or Markdown files, one per day, in a folder you choose. It doesn't import or read `export.xml`. It works from the Apple Health data on your iPhone, and you don't need to create the full archive.

The workout distance comes out as a number with an explicit unit:

- In the [fictional sample CSV](/docs/reference/generated/core/summary-day.csv), a run's distance is the row with Category `Workouts`, Metric `Running Distance`, Value `10000` and Unit `meters`.
- In the [fictional sample JSON](/docs/reference/generated/core/summary-day.json), each workout object carries `distance` (`10000`), `distanceKm` (`10`) and `distanceMi`, next to its ID and start and end timestamps.

Want per-workout CSV or JSON without parsing XML? See [exporting Apple Fitness workouts](/blog/export-apple-health-workouts/) for the row layout and the [CSV import rules](/apple-health-to-csv/) before opening files in a spreadsheet.

<a class="button" href="https://apps.apple.com/us/app/health-md/id6757763969">Get Health.md for iPhone</a>

Health.md offers weekly, yearly and Lifetime access, and eligible subscriptions start with a 7-day free trial; see [purchase details](/docs/paywall/).

The local folder export needs no Health.md account and creates no Health.md server copy by default. Synced folders follow their provider's storage rules. The separate opt-in, single-owner Health.md Cloud pilot keeps only API exports intentionally uploaded to it. It has no public signup and no automatic device sync, and isn't generally available.

## Common questions

### Why is totalDistance missing from my export.xml workouts?

Newer exports store workout totals in `<WorkoutStatistics>` child elements, and `totalDistance` is optional in the DTD. Read the `sum` and `unit` of the `HKQuantityTypeIdentifierDistance…` statistic that matches the sport, then fall back to `totalDistance` for older workouts.

### Why does my parser fail on export.xml?

If the error points into the `<!DOCTYPE HealthData [` block, or reports a duplicate `startDate`, you may have one of the iOS 16 era exports that users reported as broken. Skip the DTD and repair the repeated attribute as the script above does, or create a fresh export.

### Can I add up DistanceWalkingRunning records for a workout instead?

Only as an approximation. Records from iPhone and Apple Watch can overlap, and records nested inside a workout repeat top-level ones. Filter to one source and label the result as estimated.

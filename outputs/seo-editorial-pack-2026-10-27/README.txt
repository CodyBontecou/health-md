Health.md editorial demonstration pack — October 27, 2026

Open index.html for the review brief. All bundled health measurements and journal examples are fictional. Assets were copied from production source commit 4a1f6214a935bfcdce30301d23902ef31335a9dc and checked against live downloads.

1. Selected-data export
Open assets/2026-10-26.csv beside the four CSV screenshots. It is the exact 658-byte export used in the live walkthrough. Steps are 12,500 and sleep is 23,400 seconds. The app captures use fictional simulator fixtures and the actual CSV writer; they do not establish HealthKit authorization or physical-device qualification.

2. Finished spreadsheet and Obsidian examples
The spreadsheet ZIP includes the workbook, daily inputs, combined CSV, and instructions. The separate Obsidian ZIP includes 28 fictional notes, a Bases log, a completed review, and fixed chart snapshots. Optional interactive charts use a separate plugin; no plugin was installed or enabled by this task. Keep sample files separate from your own records.

3. Offline automation example
From this folder, run:
python3 automation/weekly_review.py --input automation/daily --output automation/weekly-review.md
Then inspect automation/weekly-review.md. It reproduces the workbook's totals from the 28 daily inputs without dependencies or network access. It starts with files already on disk and does not pair devices or schedule exports.
Run its checks with:
python3 -m unittest discover -s automation -p 'test_*.py' -v

Publisher material
- TidBITS: founder writing brief rather than a send-ready AI pitch, respecting the publisher's stated preference.
- The Sweet Setup: review draft and exact official contact route.
- MacStories: held brief, with the remaining device-transfer verification explicitly listed.
- Publisher research and public source URLs are included in publisher-research.md.
- outreach-tracker.csv starts with prepared/held statuses. No outreach was sent or external draft created.

Use the live task pages in first contact. This complete ZIP is for owner review; provide files to a publisher when requested. No review-access entitlement or purchase code is included.

See MEASUREMENT.txt for the remaining page/query evidence gap and suggested review windows. This pack does not claim a ranking improvement or a guaranteed link.

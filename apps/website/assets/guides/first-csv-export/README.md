# First CSV export captures

Captured October 27, 2026, from Health.md's real iPhone interface on an iPhone 17 Pro simulator running iOS 26.5. Website/app source base: `40f69eafe3a4d95dbc3e24e030f6b0fc52e5a103`.

All health values come from the existing `UITestHealthKitFixtures` fictional dataset. The capture build supplied that dataset to the normal selected-metric CSV rendering and local file-writing pipeline. The generic simulated UI-test success path was disabled for this capture. The resulting CSV was written to the simulator's isolated TestVault folder and opened with the app's View Exported File action.

`2026-10-26.csv` is the actual 658-byte output shown in the captures. It contains 12,500 steps and 23,400 seconds (6.5 hours) of sleep. The preview's daily-file size matches those bytes. Two generated files in the result means the CSV and optional `_healthmd_data_dictionary.json`.

The capture-only setup marked Health access connected and used a writable test folder; these images do not verify Health permission approval, physical-device data capture, or a person's record completeness. The installed Xcode 26.6 SDK cannot compile the guarded iOS 27 history-boundary API, so that unreachable branch was omitted only for this iOS 26.5 capture build. No native changes ship with the website assets.

Screenshots are full-screen captures compressed to WebP, without edited controls or fabricated output. The 28-day spreadsheet pack and the March 15 schema-reference sample are separate fictional datasets; do not describe their values as belonging to this captured export.

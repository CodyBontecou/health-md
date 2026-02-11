# Health.md — macOS Version Design

## Status: Implementation Complete (Phases 1–3), Testing & Docs (Phase 4)

This document describes the design and implementation of the macOS version of Health.md.

## Architecture

Health.md is a single Xcode project with two targets sharing a common codebase:

```
┌─────────────────────────────────────────────────────────┐
│                    Shared Code                           │
│  Models  │  Managers  │  Export  │  Theme                │
│  HealthData, HealthMetrics, FormatPreferences, etc.      │
│  HealthKitManager (#if os guards)                        │
│  VaultManager (#if os guards for bookmarks)              │
│  ExportOrchestrator (foreground + background export)     │
│  Markdown/JSON/CSV/ObsidianBases exporters               │
│  DesignSystem (#if os for iOS dark theme / macOS system) │
└───────────────┬─────────────────────┬────────────────────┘
                │                     │
        ┌───────┴───────┐     ┌───────┴────────┐
        │   iOS Target  │     │  macOS Target   │
        │               │     │                 │
        │ ContentView   │     │ MacContentView  │
        │ SchedulingMgr │     │ SchedulingMgr   │
        │ (BGTask)      │     │ (Timer+Login)   │
        │ AppDelegate   │     │ MacAppDelegate  │
        │ FolderPicker  │     │ MacFolderPicker │
        │ Components/   │     │ Views/          │
        │ Views/        │     │ MenuBarExtra    │
        └───────────────┘     └────────────────┘
```

### Key Design Decisions

1. **Option A: Native Multiplatform with HealthKit** — HealthKit is available on macOS 14+ (Apple Silicon). Health data syncs via iCloud. No custom sync infrastructure needed.

2. **Shared code with `#if os()` guards** — HealthKitManager uses background delivery on iOS vs polling timer on macOS. VaultManager uses `.withSecurityScope` bookmark options on macOS.

3. **Separate UI, shared logic** — iOS has a custom dark theme with liquid glass effects. macOS uses native system colors, NavigationSplitView, and standard Form layouts. The export engine is 100% shared.

4. **Menu bar persistence** — macOS app stays running in the menu bar. `applicationShouldTerminateAfterLastWindowClosed` returns `false`. Login Item via `SMAppService` for automatic startup.

5. **Environment-based state sharing** — `VaultManager` and `AdvancedExportSettings` are `@StateObject` at the App level and passed down via `@EnvironmentObject` so the main window, Settings window (⌘,), and menu bar widget all share the same state.

---

## Implementation Details

### Phase 1: Shared Code Extraction (Complete)

- Decoupled `WorkoutData` from `HKWorkoutActivityType` → new `WorkoutType` enum mapped at fetch time
- Extracted export formatters from `HealthData.swift` → `Shared/Export/` (5 files: ExportHelpers, MarkdownExporter, JSONExporter, CSVExporter, ObsidianBasesExporter)
- Restructured project into `Shared/iOS/macOS` folder hierarchy

### Phase 2: Platform Adaptations (Complete)

- **HealthKitManager**: `#if os(iOS)` for background delivery (`enableBackgroundDelivery`); `#if os(macOS)` for polling timer. Observer queries are shared.
- **VaultManager**: `#if os()` guards for bookmark creation/resolution options (`.withSecurityScope` on macOS, empty options on iOS).
- **ExportOrchestrator**: New shared struct with `exportDates()` (foreground, security-scoped) and `exportDatesBackground()` (caller-managed scope) methods.
- **SchedulingManager+macOS**: Timer-based scheduling (30-min check interval) + `SMAppService` Login Item + `UNUserNotificationCenter` notifications.
- **MacAppDelegate**: `NSApplicationDelegate` with notification center delegate, `applicationShouldTerminateAfterLastWindowClosed → false`, catch-up export on `applicationDidBecomeActive`.
- **FolderPicker+macOS**: Simple `NSOpenPanel` wrapper.
- **macOS target**: Added to Xcode project with proper entitlements and exception sets.

### Phase 3: macOS UI (Complete)

Seven view files in `macOS/Views/`:

| File | Lines | Purpose |
|---|---|---|
| `MacContentView.swift` | ~110 | NavigationSplitView with 4-item sidebar + HealthKit unavailable fallback |
| `MacExportView.swift` | ~230 | Export form: health status, folder, date range, options, progress, ⌘E |
| `MacMetricSelectionView.swift` | ~160 | Searchable metric picker with DisclosureGroups and category toggles |
| `MacScheduleView.swift` | ~110 | Schedule toggle, frequency/time pickers, Login Item toggle, status |
| `MacHistoryView.swift` | ~210 | HSplitView with list + detail panel, status icons, failure details |
| `MacSettingsView.swift` | ~470 | Sidebar detail settings + ⌘, window with 4 tabs (General/Format/Data/Schedule) |
| `MacMenuBarView.swift` | ~200 | Menu bar widget: status, Export Yesterday, Open/Settings/Quit buttons |
| `MacVaultFolderSection.swift` | ~60 | Reusable vault folder picker section (used in Export + Settings views) |

**Design principles:**
- Native macOS styling (system Form, List, NavigationSplitView)
- No iOS design artifacts (no liquid glass, forced dark mode, custom colors)
- Uses system colors via DesignSystem `#elseif os(macOS)` block → NSColor mapping
- Respects light/dark mode automatically

### Phase 4: Testing, Polish & Docs (Current)

**Code-level fixes applied:**
- Lifted `VaultManager` and `AdvancedExportSettings` to App-level `@StateObject` to share state across main window, Settings window, and menu bar
- Added `isExporting` guard in `SchedulingManager` to prevent concurrent exports
- Added `applicationDidBecomeActive` catch-up export trigger
- Added HealthKit unavailable screen for Intel Macs / missing Health setup
- Added vault folder status to menu bar widget
- Added export result feedback to menu bar "Export Yesterday" button
- Added macOS app icon (generated all `mac` idiom sizes: 16–1024px)
- Extracted duplicated vault folder picker UI into `MacVaultFolderSection` shared component
- Added macOS-specific HealthKit authorization guidance (System Settings redirect)
- Fixed menu bar "Open Health.md" window activation to reliably find the main window
- Fixed Settings selector compatibility (`showSettingsWindow:` vs `showPreferencesWindow:`)
- Updated README with macOS sections
- Updated this design document

**Manual testing required (on-device):**
- HealthKit authorization flow on macOS
- Security-scoped bookmark persistence across app restarts
- Login Item registration via SMAppService
- Timer-based scheduled exports firing correctly
- Notification delivery on macOS
- Window position/size restoration
- Light/dark mode rendering

---

## File Membership Rules

The Xcode project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 77). Target membership is controlled by exception sets:

- **iOS target exceptions** (exclude from iOS build): all `macOS/*.swift` and `macOS/Views/*.swift` files
- **macOS target exceptions** (exclude from macOS build): all `iOS/**/*.swift` files, `Info.plist`, `HealthMd.entitlements`

**When adding a new file:**
- New file in `macOS/` → add to iOS target's `membershipExceptions` list in `project.pbxproj`
- New file in `iOS/` → add to macOS target's `membershipExceptions` list
- New file in `Shared/` → no changes needed (included in both targets)

---

## Entitlements

### iOS (`HealthMd.entitlements`)
```xml
com.apple.developer.healthkit = true
com.apple.developer.healthkit.access = []
com.apple.developer.healthkit.background-delivery = true
```

### macOS (`HealthMd-macOS.entitlements`)
```xml
com.apple.developer.healthkit = true
com.apple.developer.healthkit.access = []
com.apple.security.app-sandbox = true
com.apple.security.files.user-selected.read-write = true
com.apple.security.files.bookmarks.app-scope = true
```

---

## Known Limitations

1. **Apple Silicon only** — HealthKit is unavailable on Intel Macs
2. **macOS 14+ required** — deployment target is 14.0 (Sonoma)
3. **iCloud Health sync required** — data syncs from iPhone/Apple Watch via iCloud
4. **Sync delay** — health data may take minutes to ~1 hour to appear on Mac
5. **No BGTaskScheduler on macOS** — scheduled exports require the app to be running (menu bar)
6. **ExportOrchestrator not yet used by iOS** — iOS still uses inline export loops; migration is optional cleanup

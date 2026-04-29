"""Page content for health.md docs.

Each page is a dict consumed by build.py. The `body` field is HTML.
Keep file paths to assets relative to the page directory:
  /docs/<slug>/index.html  →  ../assets/...
"""
from textwrap import dedent

# Single raw screenshot, centered. (Highlight variants were removed.)
def shot(raw, caption=""):
    fig = f'<figcaption>{caption}</figcaption>' if caption else ''
    return dedent(f"""\
        <figure class="shot-single">
          <img src="../../assets/docs/raw/{raw}" alt="{caption or raw}" loading="lazy">
          {fig}
        </figure>""")


# Backwards-compatible alias used throughout this file. Both `pair` and
# `single` collapse to the same single raw screenshot now that highlight
# variants have been retired.
def shot_pair(raw, _highlight=None, raw_caption="", _hi_caption=""):
    return shot(raw, raw_caption)


def shot_single(raw, caption=""):
    return shot(raw, caption)


PAGES = [
    # ─────────────────────────────── ONBOARDING ──────────────────────────────
    {
        "slug": "onboarding",
        "title": "Onboarding",
        "eyebrow": "Getting Started · Step 1",
        "lead": "A 5-step welcome flow that runs the first time you open the app. Connects HealthKit, picks a vault folder, names the export subfolder, unlocks the app, and confirms you're ready to export.",
        "hero_shot": {"raw": "12-onboarding.png", "caption": "Welcome screen"},
        "body": dedent("""
            <h2>What it does</h2>
            <p>Onboarding only appears on first launch. It guides you through everything you need to do <em>once</em> so the rest of the app just works:</p>

            <div class="options">
              <div class="option"><strong>1. Welcome</strong><p>What the app does, in one screen — Markdown export, scheduled background runs, on-device only.</p></div>
              <div class="option"><strong>2. Health Access</strong><p>Triggers iOS's HealthKit permission sheet. Tip: choose <em>Turn On All</em> for the simplest setup. You can adjust later in iOS Settings → Privacy &amp; Security → Health → health.md.</p></div>
              <div class="option"><strong>3. Pick Your Vault</strong><p>Opens the iOS document picker. Choose a folder anywhere — iCloud Drive, On My iPhone, an Obsidian vault, or any third-party file provider.</p></div>
              <div class="option"><strong>4. Unlock</strong><p>One-time purchase ($9.99) for unlimited exports. The first 3 exports are free; you can come back to this step later from the Paywall.</p></div>
              <div class="option"><strong>5. Ready</strong><p>Confirms permissions, vault, and unlock state are all set. <em>Get Started</em> dismisses onboarding for good.</p></div>
            </div>

            <div class="callout">
              <strong>Skip-friendly.</strong>
              <p style="margin-top:6px;">The Health Access step is intentionally not gated — denying iOS's permission sheet would otherwise trap you (iOS only shows it once per install). You can grant it later via Settings.</p>
            </div>

            <h2>Why these steps, in this order</h2>
            <p>HealthKit access has to be granted before the export engine can read anything. The vault picker is iOS's UIDocumentPickerViewController — it produces a security-scoped bookmark that the app stores and reuses. Picking the vault before the first export means we never have to interrupt an export run with a folder picker.</p>

            <h2>Re-running onboarding</h2>
            <p>There is no in-app reset. To redo the flow, delete and reinstall the app — your purchase will restore via <em>Restore Purchase</em> on the paywall.</p>
        """),
        "related": [
            ("Next", "../folder-vault/", "Folder & Vault — what the picker actually does."),
            ("Next", "../export/", "Run your first export."),
            ("Account", "../paywall/", "Unlock & Paywall details."),
        ],
    },

    # ─────────────────────────────── FOLDER & VAULT ──────────────────────────
    {
        "slug": "folder-vault",
        "title": "Folder & Vault",
        "eyebrow": "Getting Started · Step 2",
        "lead": "Pick where your Markdown files live and name the subfolder where exports get written. The vault is just any iOS folder — Obsidian, Files, iCloud Drive, or third-party file providers all work.",
        "hero_shot": {"raw": "10-export-modal.png", "caption": "Export modal"},
        "body": dedent("""
            <h2>What "vault" means here</h2>
            <p>The app uses <em>vault</em> as a generic name for the folder you've picked, regardless of whether you actually use Obsidian. If you do use Obsidian, point it at your Obsidian vault root. Otherwise, pick any folder — iCloud Drive's <code>Documents/Health</code>, an On My iPhone folder, etc.</p>

            <h2>How the picker works</h2>
            <p>Tapping the vault row opens iOS's standard document picker (<code>UIDocumentPickerViewController</code>). When you pick a folder, iOS returns a <em>security-scoped URL</em> — a long-lived handle that lets the app keep accessing the folder across launches without re-prompting. The app stores this as a bookmark in <code>UserDefaults</code>.</p>

            <h2>Subfolder name</h2>
            <p>After picking the vault, you're prompted to name the subfolder where exports go. The default is <code>Health</code>. Whatever you choose becomes the prefix for every exported file's path:</p>
            <pre><code>{vault}/
  {subfolder}/                 ← what you name here
    2026-04-28-monday.md
    2026-04-27-sunday.md
    ...</code></pre>

            <p>You can change the subfolder later from <em>Settings → Obsidian Vault</em>. Existing files are not moved.</p>

            <h2>Cross-app behavior</h2>
            <div class="options">
              <div class="option"><strong>Obsidian</strong><p>Pick the Obsidian vault root. Set the subfolder to e.g. <code>Health</code> so exports show up as a folder in your vault tree.</p></div>
              <div class="option"><strong>iCloud Drive</strong><p>Pick a folder under iCloud Drive. Files sync to all your Apple devices automatically.</p></div>
              <div class="option"><strong>On My iPhone</strong><p>Pick a folder you've created in Files → On My iPhone. Local-only, no sync.</p></div>
              <div class="option"><strong>Third-party providers</strong><p>Dropbox, Google Drive, Working Copy, etc. — anything that exposes a Files-app provider works the same way.</p></div>
            </div>

            <div class="callout">
              <strong>iOS quirk.</strong>
              <p style="margin-top:6px;">If iOS revokes the security-scoped bookmark (rare — usually only if the underlying folder is deleted or moved), exports will start to fail. The fix is to re-pick the vault from <em>Settings</em>.</p>
            </div>
        """),
        "related": [
            ("Previous", "../onboarding/", "Onboarding — where you first pick the vault."),
            ("Next", "../export/", "Run an export into your new vault."),
            ("Customize", "../format/", "Format Customization — how the files inside the subfolder are written."),
        ],
    },

    # ─────────────────────────────── EXPORT ──────────────────────────────────
    {
        "slug": "export",
        "title": "Export",
        "eyebrow": "Core Feature",
        "lead": "The Export tab is the main canvas. It shows whether HealthKit and your vault are connected, exposes a single Export button, and gives you a date-range modal for one-off exports.",
        "hero_shot": {"raw": "01-export.png", "caption": "Export tab"},
        "body": dedent("""
            <h2>The two badges</h2>
            <div class="options">
              <div class="option"><strong>Health badge</strong><p>Green dot = HealthKit authorized. Red = not granted. Tap to retry the iOS permission sheet (only works the first time per install — after that, iOS silently does nothing and you have to fix it in Settings → Privacy &amp; Security → Health).</p></div>
              <div class="option"><strong>Vault badge</strong><p>Green dot = a vault folder is selected. Tap to re-pick or change the vault. The label shows the folder name.</p></div>
            </div>
            <p>The <em>Export Health Data</em> button is disabled until both badges are green. This prevents the most common failure mode: trying to export with no destination.</p>

            <h2>The export modal</h2>
        """) + shot_pair("10-export-modal.png", "10-export-modal-dates.png",
                         "Export modal — full", "Highlighted date range") + dedent("""

            <p>Tapping <em>Export Health Data</em> opens this modal. From here you control:</p>

            <div class="options">
              <div class="option"><strong>Vault &amp; subfolder</strong><p>Confirms where files will land. The subfolder field is editable; saved per-export.</p></div>
              <div class="option"><strong>Start date</strong><p>The first day to export. Defaults to one week ago.</p></div>
              <div class="option"><strong>End date</strong><p>The last day to export, inclusive. Defaults to today.</p></div>
              <div class="option"><strong>Export</strong><p>Runs the export. Closes the modal and shows a progress bar on the main screen, then a toast with the result.</p></div>
            </div>

            <h2>What "exporting" actually does</h2>
            <ol>
              <li>For each day in the range, query HealthKit for every metric you've enabled.</li>
              <li>Apply your chosen format (Markdown, Bases, JSON, or CSV) and template.</li>
              <li>Write one file per day into <code>{vault}/{subfolder}/</code>.</li>
              <li>If <em>Individual Tracking</em> is on, also write one file per timestamped entry into the entries folder.</li>
              <li>If <em>Daily Note Injection</em> is on, also merge metrics into your daily notes' frontmatter.</li>
            </ol>

            <h2>Tab bar</h2>

            <p>The four tabs at the bottom of the screen — Export, Schedule, Sync, Settings — cover the entire app surface area. Everything else lives one or two layers deep inside Settings.</p>

            <div class="callout">
              <strong>Free trial limit.</strong>
              <p style="margin-top:6px;">Free users get 3 full exports. After that, tapping Export opens the paywall. <a href="../paywall/">See the Paywall page</a> for what unlocks change.</p>
            </div>
        """),
        "related": [
            ("Daily use", "../scheduling/", "Scheduling — automate this so you never tap Export again."),
            ("Customize", "../format/", "Format Customization — change what each file looks like."),
            ("Power", "../shortcuts/", "Shortcuts — trigger exports from Siri, automations, or other apps."),
        ],
    },

    # ─────────────────────────────── SCHEDULING ──────────────────────────────
    {
        "slug": "scheduling",
        "title": "Scheduling",
        "eyebrow": "Core Feature · Set & Forget",
        "lead": "Run exports automatically — daily or weekly, at a time you pick. Uses iOS background tasks plus a scheduled local notification as a fallback when the device is locked.",
        "hero_shot": {"raw": "02-schedule.png", "caption": "Schedule tab"},
        "body": dedent("""
            <h2>The Schedule tab</h2>
            <p>A status screen, not a settings panel. It tells you in one glance:</p>
            <ul>
              <li>Whether the schedule is on or off</li>
              <li>The next scheduled run, if any</li>
              <li>The last run's outcome</li>
            </ul>
            <p>One button — <em>Set Up Schedule</em> (or <em>Manage Schedule</em>) — opens the detail view.</p>

            <h2>Schedule settings</h2>
        """) + shot("13-schedule-settings.png", "Schedule settings") + dedent("""

            <div class="options">
              <div class="option"><strong>Enable Scheduled Exports</strong><p>Master toggle at the top. When off, no background runs and no notifications.</p></div>
              <div class="option"><strong>Frequency</strong><p>Daily, Weekly, or Monthly. Daily exports cover yesterday; weekly covers the previous 7 days; monthly covers the previous 30.</p></div>
              <div class="option"><strong>Time</strong><p>Hour and minute. iOS treats this as a hint, not a guarantee — see the limitations callout below.</p></div>
            </div>

            <h2>Export history</h2>
            <p>The list at the bottom of the Schedule screen records every scheduled run with its outcome. Tap a row to see details. Failed runs include a <em>Retry</em> button that re-runs that specific date range.</p>

            <h2>How iOS scheduling actually works</h2>
            <div class="callout">
              <strong>iOS limitations you should know.</strong>
              <p style="margin-top:6px;">HealthKit data isn't readable while the device is locked. Scheduled exports run via <code>BGAppRefreshTask</code>, which iOS opportunistically schedules based on usage patterns — your time setting is a target, not a contract. As a fallback, the app posts a local notification at the scheduled time if the device is locked; tap it to run the export.</p>
            </div>
            <ul>
              <li>The scheduled time is approximate. iOS may run the task earlier, later, or skip it if the device is dead/disconnected.</li>
              <li>Scheduled exports work best when your phone is regularly plugged in and unlocked at roughly the same time each day.</li>
              <li>If the export fails because the device was locked, tap the notification — that runs the export with HealthKit access.</li>
            </ul>

            <h2>Programmatic control</h2>
            <p>You can turn the schedule on/off from Shortcuts using the <em>Turn Scheduled Export On or Off</em> intent. <a href="../shortcuts/">See Shortcuts</a> for examples.</p>
        """),
        "related": [
            ("Manual", "../export/", "Export — for one-off date ranges."),
            ("Automate", "../shortcuts/", "Shortcuts — toggle the schedule from automations."),
            ("Cross-device", "../sync/", "Mac Sync — schedule on Mac too."),
        ],
    },

    # ─────────────────────────────── SYNC ────────────────────────────────────
    {
        "slug": "sync",
        "title": "Mac Sync",
        "eyebrow": "Core Feature · Cross-Device",
        "lead": "Locally pair your iPhone with the macOS app over Wi-Fi or Bluetooth. The Mac requests data, the iPhone fulfills it, and exports land directly on your desktop — no cloud service, no account.",
        "hero_shot": {"raw": "03-sync.png", "caption": "Sync tab"},
        "body": dedent("""
            <h2>What it is</h2>
            <p>Mac Sync turns the iPhone into a <em>data source</em> for the macOS companion app. The Mac runs the export pipeline (same engine, same templates), but pulls the raw HealthKit data from your phone over the local network.</p>

            <h2>How to enable</h2>
            <ol>
              <li>Install the macOS app from the Mac App Store.</li>
              <li>Open the Mac app, sign into the same iCloud account you use on iPhone (only used for device discovery).</li>
              <li>On iPhone, open the Sync tab and turn on <em>Sync to Mac</em>.</li>
              <li>The Mac and iPhone discover each other on your local network and pair automatically.</li>
            </ol>

            <h2>What's transferred</h2>
            <ul>
              <li>HealthKit samples for the date range the Mac requests</li>
              <li>Your metric selection (so the Mac knows what you want)</li>
              <li>Format / customization settings</li>
            </ul>
            <p>No raw HealthKit data leaves your devices' local network. The transport is end-to-end encrypted within Apple's network framework.</p>

            <h2>When to use it</h2>
            <div class="options">
              <div class="option"><strong>Long-running exports</strong><p>Years of historical data is faster on a Mac. Trigger from the desktop, the iPhone fulfills, files land in your Mac vault.</p></div>
              <div class="option"><strong>Desktop-only vaults</strong><p>If your Obsidian vault lives only on the Mac (no iCloud), this is the cleanest path.</p></div>
              <div class="option"><strong>Scheduled desktop exports</strong><p>Use the Mac app's scheduling so exports happen even when the iPhone is asleep — as long as both devices are on the same network at the scheduled time.</p></div>
            </div>

            <div class="callout">
              <strong>Local network required.</strong>
              <p style="margin-top:6px;">Both devices must be on the same Wi-Fi network. Cellular-only iPhones can't sync to a Mac. The first connection requires iOS's local-network permission prompt — accept it.</p>
            </div>
        """),
        "related": [
            ("Desktop", "../macos/", "macOS App — Export, Schedule, History on the Mac."),
            ("Workflow", "../scheduling/", "Scheduling — schedule exports on either side."),
        ],
    },

    # ─────────────────────────────── METRICS ─────────────────────────────────
    {
        "slug": "metrics",
        "title": "Health Metrics",
        "eyebrow": "Customization · What to Export",
        "lead": "Pick which of the 100+ HealthKit metrics across 17 categories you want exported. Search, toggle whole categories at once, or drill in for per-metric control.",
        "hero_shot": {"raw": "06-metric-selection.png", "caption": "Metric selector"},
        "body": dedent("""
            <h2>Layout</h2>
            <div class="options">
              <div class="option"><strong>Counts header</strong><p>Live readout: <em>X of N metrics · Y of 17 categories</em>. Tap-and-hold to copy the exact selection state to clipboard.</p></div>
              <div class="option"><strong>All Metrics Enabled</strong><p>Master toggle that flips every category on or off. Useful as a starting point — turn everything on, then disable what you don't care about.</p></div>
              <div class="option"><strong>Search</strong><p>Live filter across metric names and identifiers. Try "heart", "sleep", "vo2".</p></div>
            </div>

            <h2>Categories</h2>
            <p>17 HealthKit categories: Activity, Body Measurements, Cycle Tracking, Cycling, Hearing, Heart, Mindfulness, Mobility, Nutrition, Other Data, Respiratory, Running, Sleep, Symptoms, Vitals, Workouts, Swimming. Each row shows the on/off state and the live count of enabled metrics within it.</p>

            <p>Tap a category to drill into its metrics. Each metric has its own toggle and HealthKit identifier. The dot color reflects whether HealthKit currently has data for that metric on this device.</p>

            <h2>Selection scope</h2>
            <p>Your metric selection drives <em>everything</em>:</p>
            <ul>
              <li>Daily exports — only enabled metrics appear in the file</li>
              <li>Individual Tracking — only enabled metrics get per-entry files</li>
              <li>Daily Note Injection — only enabled metrics merge into frontmatter</li>
              <li>Shortcuts — date-range exports use the same selection</li>
            </ul>

            <div class="callout">
              <strong>Pro tip.</strong>
              <p style="margin-top:6px;">Start narrow. Enable Sleep, Activity, and Heart. Run an export. See what the file looks like. Then add more categories. It's faster to add than to wade through a 50-line file with metrics you don't care about.</p>
            </div>
        """),
        "related": [
            ("How", "../format/", "Format — change how the metrics you pick are written."),
            ("Granular", "../individual-tracking/", "Individual Tracking — also write one file per timestamped entry."),
            ("Obsidian", "../daily-notes/", "Daily Note Injection — push these metrics into your daily notes."),
        ],
    },

    # ─────────────────────────────── FORMAT ──────────────────────────────────
    {
        "slug": "format",
        "title": "Format Customization",
        "eyebrow": "Customization · How Files Look",
        "lead": "Control output formatting without changing what's collected. Pick a file format, date / time / unit conventions, customize the YAML frontmatter, and choose a Markdown template.",
        "hero_shot": {"raw": "07-format-customization.png", "caption": "Format Customization"},
        "body": dedent("""
            <h2>Output formats</h2>
            <div class="options">
              <div class="option"><strong>Markdown (.md)</strong><p>Default. One file per day. YAML frontmatter (optional) plus headed sections per category.</p></div>
              <div class="option"><strong>Obsidian Bases</strong><p>Markdown with structured frontmatter optimized for Obsidian's <a href="https://help.obsidian.md/Plugins/Bases">Bases</a> plugin. Numeric properties stay numeric, dates stay dates.</p></div>
              <div class="option"><strong>JSON</strong><p>One JSON file per day. Easy to script against. Schema mirrors HealthKit identifiers.</p></div>
              <div class="option"><strong>CSV</strong><p>One CSV per day. Columns are metric identifiers; rows are timestamped entries.</p></div>
            </div>

            <h2>Date &amp; time</h2>
            <p>Pickers for date format (e.g. <code>YYYY-MM-DD</code>, <code>MMM d, yyyy</code>) and time format (12-hour, 24-hour). The preview block at the bottom of the screen updates live as you change settings.</p>

            <h2>Unit system</h2>
            <p>Toggle between <em>Metric</em> and <em>Imperial</em>. Affects distance (m/km vs ft/mi), weight (kg vs lb), temperature (°C vs °F), and a few others. HealthKit always stores in canonical units; conversion happens at export time.</p>

            <h2>Frontmatter fields</h2>
            <p>Tapping <em>Frontmatter Fields</em> opens a dedicated editor:</p>
            <ul>
              <li>Toggle individual built-in fields (date, weekday, totalSteps, etc.)</li>
              <li>Rename a field — useful if your Obsidian setup expects different keys</li>
              <li>Add custom fields with static values (e.g. <code>type: health</code>)</li>
              <li>Add placeholder fields that resolve at export time (e.g. <code>weather: {weather}</code>)</li>
            </ul>

            <h2>Markdown template</h2>
            <p>Tapping <em>Markdown Template</em> opens a template editor with several built-in styles (Compact, Sections, Detailed) plus a fully custom mode. The preview block shows the result for today's data.</p>

            <h2>Preview</h2>
            <p>At the bottom of the Format screen, a live preview block renders today's data with your current settings. This is the fastest way to iterate — change a toggle, look at the preview, repeat.</p>
        """),
        "related": [
            ("What", "../metrics/", "Health Metrics — pick the data first."),
            ("Granular", "../individual-tracking/", "Individual Tracking — different output entirely (per-entry files)."),
            ("Obsidian", "../daily-notes/", "Daily Note Injection — uses the same frontmatter fields."),
        ],
    },

    # ─────────────────────────────── INDIVIDUAL TRACKING ─────────────────────
    {
        "slug": "individual-tracking",
        "title": "Individual Entry Tracking",
        "eyebrow": "Customization · Granular",
        "lead": "Optionally write one file per timestamped entry — every workout, every blood-pressure reading, every mood log gets its own Markdown file with the timestamp baked into the filename.",
        "hero_shot": {"raw": "08-individual-tracking.png", "caption": "Individual Tracking"},
        "body": dedent("""
            <h2>When to use it</h2>
            <p>Daily exports give you one file per day with summaries. <em>Individual tracking</em> is for the case where you want to <em>cite a single event</em> — link to a specific workout from a journal note, or backlink a mood entry into a weekly review.</p>

            <p>This is on top of the daily export, not instead. With both on, you get both kinds of files.</p>

            <h2>Two-step setup</h2>
            <p>The settings UI is intentionally a two-step funnel:</p>
            <ol>
              <li><strong>Master switch.</strong> Turn the feature on globally.</li>
              <li><strong>Per-metric selection.</strong> Choose <em>which</em> metrics get individual files. Most people don't want a file per heart-rate reading (10,000 / day) — but they do want one per workout (~1 / day).</li>
            </ol>

            <h2>Quick actions</h2>
            <div class="options">
              <div class="option"><strong>Enable Suggested Metrics</strong><p>Sensible defaults: mood, symptoms, workouts, blood pressure, blood glucose. The metrics where one-file-per-entry actually makes sense.</p></div>
              <div class="option"><strong>Enable All Metrics</strong><p>Everything. Be careful — this can produce thousands of files per day.</p></div>
              <div class="option"><strong>Disable All Metrics</strong><p>Clears the per-metric selection without flipping the master switch.</p></div>
            </div>

            <h2>Folder structure</h2>
            <div class="options">
              <div class="option"><strong>Entries Folder</strong><p>Vault-relative path where individual files land. Default: <code>entries</code>.</p></div>
              <div class="option"><strong>Organize by Category</strong><p>If on, entries are nested under category subfolders (<code>entries/workouts/</code>, <code>entries/symptoms/</code>). If off, all entries sit in one flat folder.</p></div>
            </div>

            <h2>Filename template</h2>
            <p>Default: <code>{date}_{time}_{metric}</code>. Available placeholders: <code>{date}</code>, <code>{time}</code>, <code>{metric}</code>, <code>{category}</code>. Example output:</p>
            <pre><code>{vault}/entries/workouts/2026-04-28_07-32_workout.md
{vault}/entries/symptoms/2026-04-28_14-12_headache.md
{vault}/entries/blood-pressure/2026-04-28_19-45_blood-pressure.md</code></pre>

            <div class="callout">
              <strong>Heads up.</strong>
              <p style="margin-top:6px;">Only categories where you've enabled at least one metric in <em>Health Metrics</em> show up here. Enable a metric there first, then come back to choose whether it gets per-entry tracking.</p>
            </div>
        """),
        "related": [
            ("Prereq", "../metrics/", "Health Metrics — enable metrics first."),
            ("Output", "../format/", "Format — applies to entry files too."),
            ("Alt", "../daily-notes/", "Daily Note Injection — different way to attach metrics to notes."),
        ],
    },

    # ─────────────────────────────── DAILY NOTES ─────────────────────────────
    {
        "slug": "daily-notes",
        "title": "Daily Note Injection",
        "eyebrow": "Customization · Obsidian Workflow",
        "lead": "Merge selected health metrics into the YAML frontmatter (and optionally the body) of your existing daily notes — the ones you write in Obsidian or any other Markdown app.",
        "hero_shot": {"raw": "09-daily-note-injection.png", "caption": "Daily Note Injection"},
        "body": dedent("""
            <h2>What it does</h2>
            <p>If you keep daily notes (e.g. <code>Daily/2026-04-28.md</code>), turn this on and the app will <em>merge</em> your selected metrics into the YAML frontmatter of those notes on every export — without touching the rest of your note content.</p>

            <p>Optionally, the app can also inject Markdown sections (Sleep, Activity, Heart, etc.) into the note body. Those sections are <em>app-managed</em>: replaced cleanly on each export. Headings you write yourself stay untouched.</p>

            <h2>Location</h2>
            <div class="options">
              <div class="option"><strong>Folder</strong><p>Vault-relative path to your daily notes folder. Default <code>Daily</code>. Leave empty to target the vault root. Examples: <code>Daily</code>, <code>Journal/Daily</code>.</p></div>
              <div class="option"><strong>Filename</strong><p>Pattern for the note filename without extension. Default <code>{date}</code> resolves to <code>2026-04-28</code>.</p></div>
            </div>

            <h2>Filename placeholders</h2>
            <p>Mix and match:</p>
            <ul>
              <li><code>{date}</code> — full ISO date (<code>2026-04-28</code>)</li>
              <li><code>{year}</code>, <code>{month}</code>, <code>{day}</code></li>
              <li><code>{weekday}</code> — short name (<code>Tue</code>)</li>
              <li><code>{monthName}</code> — long name (<code>April</code>)</li>
              <li><code>{quarter}</code> — Q1 / Q2 / Q3 / Q4</li>
            </ul>
            <p>Example: <code>{year}/{monthName}/{date}-{weekday}</code> → <code>2026/April/2026-04-28-Tue.md</code>. The preview line below the field shows the resolved path live.</p>

            <h2>Options</h2>
            <div class="options">
              <div class="option"><strong>Create note if missing</strong><p>If the daily note doesn't exist for a given date, create a fresh one. Leave off if you create your own daily notes via Obsidian Templater or a similar plugin.</p></div>
              <div class="option"><strong>Inject metric sections</strong><p>Also write Sleep, Activity, Heart, etc. headings into the note body. App-managed, replaced cleanly on each export. Off by default.</p></div>
            </div>

            <h2>Which metrics get injected</h2>
            <p>Whatever you've selected in <em>Health Metrics</em>. There is no separate selector here. Change your metric selection there, and Daily Note Injection follows.</p>

            <h2>Frontmatter preview</h2>
            <p>The bottom of the Daily Note Injection screen has a live preview of the frontmatter that will be merged. This updates as you change metric selection or the format customization frontmatter fields.</p>

            <div class="callout">
              <strong>How merging works.</strong>
              <p style="margin-top:6px;">If your existing daily note already has frontmatter, the app preserves your keys and adds/updates only the keys it owns. App-managed body sections are wrapped in HTML comments so re-runs are idempotent.</p>
            </div>
        """),
        "related": [
            ("Prereq", "../metrics/", "Health Metrics — pick what gets injected."),
            ("Format", "../format/", "Frontmatter Fields editor — rename keys, add custom fields."),
            ("Granular", "../individual-tracking/", "Individual Tracking — alternative for per-event tracking."),
        ],
    },

    # ─────────────────────────────── SHORTCUTS ───────────────────────────────
    {
        "slug": "shortcuts",
        "title": "Shortcuts &amp; App Intents",
        "eyebrow": "Integrations · Automate",
        "lead": "Eight App Intents let you trigger exports, fetch summaries, and toggle the schedule from Siri, the Shortcuts app, Focus filters, automations, and any other AppIntent-aware host.",
        "body": dedent("""
            <h2>Available intents</h2>
            <div class="options">
              <div class="option"><strong>Export Yesterday's Health Data</strong><p>Zero-parameter shortcut. The fast path for &quot;just export yesterday's data and shut up about it.&quot; Same engine as the manual export.</p></div>
              <div class="option"><strong>Export Health Data for a Date</strong><p>Single <em>Date</em> parameter. Time-of-day is ignored. Useful in calendar-driven automations.</p></div>
              <div class="option"><strong>Export Health Data for Date Range</strong><p><em>Start Date</em> and <em>End Date</em> parameters, inclusive on both ends. Use for backfills.</p></div>
              <div class="option"><strong>Export Last N Days of Health Data</strong><p><em>Number of Days</em> parameter (1–366). Ends yesterday. Default 7. Good for &quot;every Sunday, export last 7 days&quot; automations.</p></div>
              <div class="option"><strong>Get Health Summary for a Date</strong><p>Returns a structured snapshot — steps, active calories, sleep, heart rate — without writing anything to the vault. Use this in Shortcuts to feed values into other apps.</p></div>
              <div class="option"><strong>Get Last Export Status</strong><p>Returns the timestamp, success state, day count, and any failure reason from the most recent export run. Pair with notifications to alert when a scheduled run fails.</p></div>
              <div class="option"><strong>Turn Scheduled Export On or Off</strong><p>Boolean parameter. Use to suspend the schedule (e.g. on vacation Focus) and resume it later.</p></div>
              <div class="option"><strong>Export Health Data</strong><p>Generic export — uses the date range from the in-app Export modal's last state. Less common; the date-range variants are usually clearer.</p></div>
            </div>

            <h2>Where to find them</h2>
            <p>Open the Shortcuts app on iOS or macOS. Tap the <em>+</em> button to create a new shortcut, search for &quot;Health.md&quot; or any of the intent titles above. They live under the <em>Health</em> category.</p>
            <p>Most intents have <code>openAppWhenRun = false</code>, so they execute headlessly — no app launch, no UI flash. They work from automations, Focus filters, the Hey Siri handoff, and the Action Button.</p>

            <h2>Recipe: nightly export with confirmation</h2>
            <ol>
              <li><strong>Personal Automation</strong> → <em>Time of Day</em> → 11:30 PM, every day.</li>
              <li><em>Export Yesterday's Health Data</em> intent.</li>
              <li><em>Get Last Export Status</em> intent.</li>
              <li><em>Show Notification</em> with the result.</li>
            </ol>

            <h2>Recipe: backfill on a one-off</h2>
            <ol>
              <li>Create a shortcut.</li>
              <li><em>Export Health Data for Date Range</em> with start = 2024-01-01, end = 2024-12-31.</li>
              <li>Run from Shortcuts. Walks the year, writes one file per day. May take a few minutes for full years.</li>
            </ol>

            <h2>Recipe: pause schedule on vacation</h2>
            <ol>
              <li><strong>Focus filter</strong>: when <em>Vacation</em> Focus turns on, run <em>Turn Scheduled Export On or Off</em> with Enabled = false.</li>
              <li>When Focus turns off, run again with Enabled = true.</li>
            </ol>

            <div class="callout">
              <strong>Authorization required.</strong>
              <p style="margin-top:6px;">Intents inherit your in-app HealthKit permission and vault selection. They will fail with a clear error if the app hasn't been opened-and-set-up at least once on this device.</p>
            </div>
        """),
        "related": [
            ("Source", "../scheduling/", "Scheduling — the in-app equivalent of the toggle intent."),
            ("Source", "../export/", "Export — the in-app equivalent of the date-range intents."),
        ],
    },

    # ─────────────────────────────── MAC ─────────────────────────────────────
    {
        "slug": "macos",
        "title": "macOS App",
        "eyebrow": "Integrations · Desktop",
        "lead": "Native Mac companion. Same export engine, native Mac UI, menu bar, and the option to schedule desktop exports while the iPhone fulfills the data.",
        "body": dedent("""
            <p>The Mac app mirrors the iOS feature set with one major addition: it can be the <em>caller</em> of an export, with the iPhone acting as the data source over Mac Sync. The export pipeline runs on the Mac; data flows in over the local network.</p>

            <h2>Panes</h2>
            <div class="options">
              <div class="option"><strong>Export</strong><p>Manual export with a date range, vault picker, and progress bar. Identical to iOS in concept; native Mac controls.</p></div>
              <div class="option"><strong>Sync</strong><p>Pairing UI for iPhone discovery. Shows the connected iPhone's name and last sync timestamp.</p></div>
              <div class="option"><strong>Schedule</strong><p>Desktop scheduling. Uses <code>NSBackgroundActivityScheduler</code> instead of iOS's BGTaskScheduler — typically more reliable since macOS isn't as aggressive about suspending apps.</p></div>
              <div class="option"><strong>History</strong><p>Same export-history list as iOS, with retry on failed runs.</p></div>
              <div class="option"><strong>Settings</strong><p>Format customization, metric selection, vault picker, all the same options as iOS.</p></div>
              <div class="option"><strong>Menu bar</strong><p>Status icon with quick actions: Export Now, Open Vault, Toggle Schedule, Open App.</p></div>
            </div>

            <div class="shot-row">
              <figure class="shot-card">
                <img src="../../assets/screenshots/macos/01_mac_export.png" alt="macOS — Export" loading="lazy">
                <figcaption>Export</figcaption>
              </figure>
              <figure class="shot-card">
                <img src="../../assets/screenshots/macos/02_mac_sync.png" alt="macOS — Sync" loading="lazy">
                <figcaption>Sync</figcaption>
              </figure>
            </div>
            <div class="shot-row">
              <figure class="shot-card">
                <img src="../../assets/screenshots/macos/03_mac_schedule.png" alt="macOS — Schedule" loading="lazy">
                <figcaption>Schedule</figcaption>
              </figure>
              <figure class="shot-card">
                <img src="../../assets/screenshots/macos/04_mac_settings.png" alt="macOS — Settings" loading="lazy">
                <figcaption>Settings</figcaption>
              </figure>
            </div>

            <h2>Setup</h2>
            <ol>
              <li>Buy the macOS app on the Mac App Store. Same family-share entitlement as the iOS app.</li>
              <li>Open. Sign into the same iCloud account as your iPhone (only used for device discovery).</li>
              <li>On iPhone, turn on Mac Sync. The Mac shows your phone in the Sync pane.</li>
              <li>Pick a vault on Mac (a folder in iCloud Drive, on disk, or anywhere accessible).</li>
              <li>Run an export. Data flows from iPhone → Mac → vault.</li>
            </ol>

            <div class="callout">
              <strong>This page covers the v1.2 macOS UI.</strong>
              <p style="margin-top:6px;">Annotated highlight variants for the Mac panes are pending — once captured, they'll replace the App Store thumbnails above.</p>
            </div>
        """),
        "related": [
            ("Setup", "../sync/", "Mac Sync — pair iPhone and Mac."),
            ("Workflow", "../scheduling/", "Scheduling — desktop scheduling is more reliable than iOS."),
        ],
    },

    # ─────────────────────────────── PAYWALL ─────────────────────────────────
    {
        "slug": "paywall",
        "title": "Unlock &amp; Paywall",
        "eyebrow": "Account · Pricing",
        "lead": "One-time purchase, no subscription. Three free exports to try the app, then a single $9.99 unlock for unlimited use across iPhone, iPad, and Mac.",
        "hero_shot": {"raw": "11-paywall.png", "caption": "Paywall"},
        "body": dedent("""
            <h2>Pricing</h2>
            <ul>
              <li><strong>$9.99</strong> one-time, on the Apple platform store.</li>
              <li>Family Sharing supported — buy once, share with up to 5 family members.</li>
              <li>iOS / iPadOS / macOS — same purchase covers all three.</li>
              <li>No subscription. No server-side account. The unlock is a StoreKit transaction tied to your Apple ID.</li>
            </ul>

            <h2>What's included free</h2>
            <ul>
              <li>3 full exports (any date range).</li>
              <li>Full HealthKit access, vault picker, format customization, metric selection — everything works.</li>
              <li>The cap is on <em>completed</em> exports, not days exported. A single multi-year backfill counts as 1.</li>
            </ul>

            <h2>What unlocks change</h2>
            <ul>
              <li>Unlimited exports.</li>
              <li>Scheduled background exports.</li>
              <li>All future features.</li>
              <li>Shortcuts intents work without limits.</li>
            </ul>

            <h2>Restore a previous purchase</h2>
            <p>Tap <em>Restore Purchase</em> on the paywall. The app queries StoreKit for any prior purchases tied to the signed-in Apple ID. This is the path to use after reinstalling the app or moving to a new device.</p>

            <h2>Refunds &amp; support</h2>
            <p>Refunds go through Apple — open a request at <a href="https://reportaproblem.apple.com">reportaproblem.apple.com</a>. For app-side support, email <a href="mailto:cody@isolated.tech">cody@isolated.tech</a>.</p>
        """),
        "related": [
            ("Setup", "../onboarding/", "Onboarding — where the unlock step appears for the first time."),
            ("Use", "../export/", "Export — what unlimited buys you."),
        ],
    },
]

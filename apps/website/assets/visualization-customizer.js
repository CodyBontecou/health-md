(function () {
  var storageKey = "healthmd-viz-studio-v3";
  var dataUrl = "/assets/visualizations-data/health-sample.json";
  var app;
  var sampleData = [];
  var resizeTimer = 0;
  var parameterRenderTimer = 0;

  var state = {
    visualization: "activity-rings",
    themeMode: "auto",
    colorScheme: "theme",
    dataFilter: "Activity",
    parameterOverrides: {}
  };

  var visualizations = [
    // Overview and reusable trend components
    viz("intro-stats", "Intro Stats", "Overview", "html", "Four-up overview card for activity, heart, sleep, and distance.", ["overview", "summary"], { type: "intro-stats", to: "2026-05-17", last: 30 }),
    viz("summary-card", "Summary Card", "Overview", "html", "KPI card with sparkline and prior-window comparison for a selected metric.", ["overview", "trend", "heart", "steps", "sleep"], { type: "summary-card", metric: "heart-rate", to: "2026-05-17", last: 30, compareWindow: "same-length" }),
    viz("trend-tile", "Trend Tile", "Overview", "html", "Compact trend tile with direction, percent change, and consistency narrative.", ["overview", "trend", "heart", "activity"], { type: "trend-tile", metric: "resting-heart-rate", to: "2026-05-17", last: 30, currentWindow: 14, priorWindow: 14 }),

    // Activity / fitness
    viz("activity-rings", "Activity Rings", "Activity", "canvas", "Move, Exercise, and Stand rings rendered by the Obsidian plugin.", ["activity", "rings", "goals"], { type: "activity-rings", to: "2026-05-17", last: 1, height: 260, moveGoal: 650, exerciseGoal: 45, standGoal: 12 }),
    viz("activity-heatmap", "Activity Heatmap", "Activity", "canvas", "Calendar-style density view for daily activity across the export window.", ["activity", "steps", "calendar", "heatmap"], { type: "activity-heatmap", metric: "steps", to: "2026-05-17", last: 30, height: 300 }),
    viz("bar-chart", "Bar Chart", "Activity", "canvas", "Daily metric bars with plugin goal and average reference lines.", ["activity", "steps", "metric", "goals"], { type: "bar-chart", metric: "steps", to: "2026-05-17", last: 7, height: 360, goal: 10000, showAverage: "true" }),
    viz("step-spiral", "Step Spiral", "Activity", "canvas", "Spiral step pattern that makes weekly activity rhythms easy to see.", ["activity", "steps", "spiral"], { type: "step-spiral", to: "2026-05-17", last: 30, height: 420 }),
    viz("weekday-average", "Weekday Average", "Activity", "canvas", "Average metric values grouped by weekday with plugin aggregation logic.", ["activity", "steps", "weekday", "trend"], { type: "weekday-average", metric: "steps", weekStart: "monday", to: "2026-05-17", last: 30, height: 360 }),

    // Heart
    viz("heart-range", "Heart Range", "Heart", "canvas", "Daily min, max, and average heart-rate ranges from the plugin renderer.", ["heart", "heart-rate", "range"], { type: "heart-range", metric: "heart-rate", to: "2026-05-17", last: 14, height: 360 }),
    viz("heart-terrain", "Heart Terrain", "Heart", "canvas", "Layered terrain chart for resting, average, and max heart-rate changes.", ["heart", "heart-rate", "terrain"], { type: "heart-terrain", to: "2026-05-17", last: 30, height: 360 }),
    viz("hrv-trend", "HRV Trend", "Heart", "canvas", "Heart-rate variability trend chart drawn from bundled Health.md samples.", ["heart", "hrv", "trend"], { type: "hrv-trend", to: "2026-05-17", last: 30, height: 360 }),

    // Sleep
    viz("sleep-architecture", "Sleep Architecture", "Sleep", "canvas", "Stacked sleep architecture view for deep, REM, core, and awake time.", ["sleep", "stages", "architecture"], { type: "sleep-architecture", to: "2026-05-17", last: 14, height: 380 }),
    viz("sleep-polar", "Sleep Polar", "Sleep", "canvas", "Circular sleep timing visualization for schedule consistency.", ["sleep", "schedule", "polar"], { type: "sleep-polar", to: "2026-05-17", last: 14, height: 420 }),
    viz("sleep-quality-bars", "Sleep Quality Bars", "Sleep", "canvas", "Nightly sleep-stage composition using deep, REM, core, and awake colors.", ["sleep", "stages", "quality"], { type: "sleep-quality-bars", to: "2026-05-17", last: 14, height: 360 }),
    viz("sleep-schedule", "Sleep Schedule", "Sleep", "canvas", "Bedtime and wake consistency across the selected Health.md export window.", ["sleep", "schedule", "duration"], { type: "sleep-schedule", to: "2026-05-17", last: 14, height: 420, sleepGoal: 8 }),

    // Respiratory / vitals / mobility
    viz("breathing-wave", "Breathing Wave", "Vitals", "canvas", "Respiratory rhythm wave for breathing-rate trends.", ["vitals", "respiratory", "breathing"], { type: "breathing-wave", to: "2026-05-17", last: 30, height: 340 }),
    viz("oxygen-range", "Oxygen Range", "Vitals", "canvas", "Daily SpO₂ range visualization using the plugin range chart core.", ["vitals", "oxygen", "range"], { type: "oxygen-range", metric: "blood-oxygen", to: "2026-05-17", last: 14, height: 360 }),
    viz("oxygen-river", "Oxygen River", "Vitals", "canvas", "Flowing oxygen saturation river chart for spotting respiratory variability.", ["vitals", "oxygen", "river"], { type: "oxygen-river", to: "2026-05-17", last: 30, height: 340 }),
    viz("vitals-rings", "Vitals Rings", "Vitals", "canvas", "Ring dashboard for current-day vitals such as oxygen, respiratory rate, and temperature.", ["vitals", "rings", "respiratory"], { type: "vitals-rings", to: "2026-05-17", last: 1, height: 320 }),
    viz("walking-symmetry", "Walking Symmetry", "Mobility", "canvas", "Mobility-focused view for walking symmetry and gait metrics.", ["mobility", "walking", "gait"], { type: "walking-symmetry", to: "2026-05-17", last: 30, height: 340 }),

    // Mindfulness / mood
    viz("mood-trend", "Mood Trend", "Mindfulness", "canvas", "State of Mind trend with sleep and exercise context behind the mood line.", ["mindfulness", "mood", "state-of-mind", "trend"], { type: "mood-trend", to: "2026-05-17", last: 30, height: 360 }),
    viz("mood-calendar-heatmap", "Mood Calendar Heatmap", "Mindfulness", "canvas", "Calendar heatmap colored by State of Mind valence.", ["mindfulness", "mood", "calendar", "heatmap"], { type: "mood-calendar-heatmap", to: "2026-05-17", last: 30, height: 330 }),
    viz("mood-sleep-scatter", "Mood × Sleep Scatter", "Mindfulness", "canvas", "Scatter plot connecting mood valence with sleep duration.", ["mindfulness", "mood", "sleep", "scatter"], { type: "mood-sleep-scatter", to: "2026-05-17", last: 30, height: 360 }),
    viz("mood-day-timeline", "Mood Day Timeline", "Mindfulness", "canvas", "Intraday timeline for daily mood and momentary emotion entries.", ["mindfulness", "mood", "timeline"], { type: "mood-day-timeline", to: "2026-05-17", last: 30, height: 360 }),
    viz("mood-association-breakdown", "Mood Association Breakdown", "Mindfulness", "canvas", "Breaks down mood by association labels such as work, friends, or fitness.", ["mindfulness", "mood", "associations"], { type: "mood-association-breakdown", to: "2026-05-17", last: 30, height: 360, limit: 8 }),
    viz("mood-label-cloud", "Mood Label Cloud", "Mindfulness", "canvas", "Weighted label cloud colored by average mood valence.", ["mindfulness", "mood", "labels", "cloud"], { type: "mood-label-cloud", to: "2026-05-17", last: 30, height: 340, limit: 12 }),
    viz("mood-volatility", "Mood Volatility", "Mindfulness", "canvas", "Bars show intraday mood range with a line for the daily average.", ["mindfulness", "mood", "volatility"], { type: "mood-volatility", to: "2026-05-17", last: 30, height: 360 }),
    viz("mood-kind-split", "Mood Kind Split", "Mindfulness", "canvas", "Compares daily moods with momentary emotions.", ["mindfulness", "mood", "daily", "momentary"], { type: "mood-kind-split", to: "2026-05-17", last: 30, height: 360 }),
    viz("mood-circadian-clock", "Mood Circadian Clock", "Mindfulness", "canvas", "Clock-style view of mood entries by time of day.", ["mindfulness", "mood", "circadian", "clock"], { type: "mood-circadian-clock", to: "2026-05-17", last: 30, height: 420 }),
    viz("mood-recovery-tile", "Mood Recovery Tile", "Mindfulness", "canvas", "Composite recovery score from mood, sleep, HRV, and exercise.", ["mindfulness", "mood", "recovery", "sleep", "hrv"], { type: "mood-recovery-tile", to: "2026-05-17", last: 30, height: 260 }),
    viz("mood-association-matrix", "Mood Association Matrix", "Mindfulness", "canvas", "Matrix connecting mood labels with associations.", ["mindfulness", "mood", "matrix", "associations"], { type: "mood-association-matrix", to: "2026-05-17", last: 30, height: 420, metric: "valence", labels: 6, associations: 6 }),

    // Workouts
    viz("workout-log", "Workout Log", "Workouts", "canvas", "Timeline-style workout log with duration, distance, calories, and intensity.", ["workouts", "activity", "log"], { type: "workout-log", to: "2026-05-17", last: 30, height: 420 }),
    viz("workout-heart-rate", "Workout Heart Rate", "Workouts", "canvas", "Detailed heart-rate trace for the selected workout.", ["workouts", "heart", "heart-rate"], { type: "workout-heart-rate", to: "2026-05-17", last: 30, height: 360, date: "2026-05-16", workout: 0 }),
    viz("workout-zones", "Workout Zones", "Workouts", "canvas", "Heart-rate zone distribution for a selected workout.", ["workouts", "heart", "zones"], { type: "workout-zones", to: "2026-05-17", last: 30, height: 320, date: "2026-05-16", workout: 0 }),
    viz("workout-trends", "Workout Trends", "Workouts", "canvas", "Workout trend chart across the selected history window.", ["workouts", "trend", "fitness"], { type: "workout-trends", to: "2026-05-17", last: 30, height: 360, metric: "duration" }),
    viz("workout-map", "Workout Map", "Workouts", "html", "Route map for GPS-enabled workouts, using the plugin's workout map renderer.", ["workouts", "map", "route", "gps"], { type: "workout-map", to: "2026-05-17", last: 30, height: 360, date: "2026-05-16", workout: 0, colorBy: "speed" }),
    viz("workout-intervals", "Workout Intervals", "Workouts", "html", "Lap, split, and interval table for the selected workout.", ["workouts", "intervals", "laps", "splits"], { type: "workout-intervals", to: "2026-05-17", last: 30, date: "2026-05-16", workout: 0 }),

    // Medications
    viz("medication-overview", "Medication Overview", "Medications", "html", "Full medication dashboard with inventory, adherence, status, trends, and recent dose events.", ["medications", "adherence", "inventory"], { type: "medication-overview", to: "2026-05-17", last: 30, trend: "daily", limit: 8 }),
    viz("medication-inventory", "Medication Inventory", "Medications", "html", "Medication inventory summary from Health.md medication exports.", ["medications", "inventory"], { type: "medication-inventory", to: "2026-05-17", last: 30 }),
    viz("medication-adherence-summary", "Medication Adherence Summary", "Medications", "html", "Taken, skipped, and other dose status rollup.", ["medications", "adherence", "summary"], { type: "medication-adherence-summary", to: "2026-05-17", last: 30 }),
    viz("medication-dose-status", "Medication Dose Status", "Medications", "html", "Per-medication dose status breakdown with adherence bars.", ["medications", "dose", "status"], { type: "medication-dose-status", to: "2026-05-17", last: 30 }),
    viz("medication-adherence-trend", "Medication Adherence Trend", "Medications", "html", "Daily, weekly, or monthly medication adherence trend columns.", ["medications", "adherence", "trend"], { type: "medication-adherence-trend", to: "2026-05-17", last: 30, trend: "daily" }),
    viz("medication-recent-dose-events", "Medication Recent Dose Events", "Medications", "html", "Recent medication dose event table.", ["medications", "dose", "events"], { type: "medication-recent-dose-events", to: "2026-05-17", last: 30, limit: 10 })
  ];

  var categoryLabels = {
    all: "All data",
    Overview: "Overview & trends",
    Activity: "Activity & fitness",
    Heart: "Heart",
    Sleep: "Sleep",
    Vitals: "Respiratory & vitals",
    Mobility: "Mobility",
    Mindfulness: "Mindfulness & mood",
    Workouts: "Workouts",
    Medications: "Medications"
  };

  var dataFilterSlugs = {
    all: "all-health-data",
    Overview: "overview-trends",
    Activity: "activity-fitness",
    Heart: "heart-health",
    Sleep: "sleep-analysis",
    Vitals: "respiratory-vitals",
    Mobility: "mobility-gait",
    Mindfulness: "mindfulness-mood",
    Workouts: "workout-analytics",
    Medications: "medication-adherence"
  };

  var colorSchemeSlugs = {
    theme: "theme-colors",
    default: "default-colors",
    ocean: "ocean-colors",
    forest: "forest-colors",
    sunset: "sunset-colors",
    aurora: "aurora-colors",
    monochrome: "monochrome-colors"
  };

  var colorSchemeOptions = [
    palette("theme", "Theme", "Matches your current site and Obsidian theme.", ["var(--color-tertiary)", "var(--color-teal-700)", "var(--color-red-800)"]),
    palette("default", "Default", "Health.md teal, gold, and red defaults.", ["#2dd4bf", "#f59e0b", "#ef4444"]),
    palette("ocean", "Ocean", "Cool blues for activity and sleep views.", ["#0ea5e9", "#38bdf8", "#e11d48"]),
    palette("forest", "Forest", "Greens and limes with warm heart accents.", ["#22c55e", "#84cc16", "#ef4444"]),
    palette("sunset", "Sunset", "Orange and pink for high-contrast dashboards.", ["#f97316", "#ec4899", "#ef4444"]),
    palette("aurora", "Aurora", "Purple and cyan with vivid highlights.", ["#a855f7", "#06b6d4", "#f43f5e"]),
    palette("monochrome", "Monochrome", "Neutral slate tones for calmer notes.", ["#94a3b8", "#64748b", "#475569"])
  ];

  var commonVisualizationOptions = [
    option("type", "visualization id", "required", "Selects the renderer, for example heart-terrain or summary-card."),
    option("width", "pixels", "plugin setting", "Maximum render width. Canvas charts shrink to the note width."),
    option("height", "pixels", "plugin setting", "Render height. Some charts may expand vertically to fit their rows."),
    option("from", "date or datetime", "none", "Start of the filtered data window, inclusive."),
    option("to", "date or datetime", "none", "End of the filtered data window, inclusive. Also anchors last."),
    option("last", "number of days", "none", "Calendar-day window ending at to, or today when to is omitted."),
    option("theme", "auto, dark, light", "plugin setting", "Controls whether the block follows Obsidian or forces a light/dark theme."),
    option("colorScheme / palette", "theme, default, ocean, forest, sunset, aurora, monochrome", "plugin setting", "Chooses the semantic color palette for the block."),
    option("background / bg, foreground / fg, muted", "CSS color", "resolved theme", "Overrides the chart surface and label colors for one block."),
    option("accent, secondary, heart, sleepDeep, sleepRem, sleepCore, sleepAwake", "CSS color", "resolved palette", "Overrides semantic health colors for one block.")
  ];

  var visualizationDocs = {
    "intro-stats": doc("Responsive HTML summary of the selected data window: totals, averages, sleep highlights, and available vitals.", "Activity, heart, sleep, and vitals summaries.", []),
    "summary-card": doc("Apple Health-style KPI card with a large current value, sparkline, range text, and prior-period delta.", "The selected metric across the filtered window.", [
      option("metric", "heart-rate, steps, sleep-duration, active-calories, hrv, blood-oxygen, respiratory-rate", "heart-rate", "Chooses the KPI, unit, color, and data extractor."),
      option("compareWindow", "same-length, week, month", "same-length", "Chooses the comparison period. Week needs at least 14 days; month needs at least 60 days.")
    ]),
    "trend-tile": doc("Compact Trends-tab card with direction, percent change, narrative, and a two-period sparkline.", "Trendable daily metric values over two adjacent periods.", [
      option("metric", "resting-heart-rate, hrv, steps, vo2max, walking-speed, sleep-duration, active-calories", "resting-heart-rate", "Chooses the trend metric and preferred direction."),
      option("currentWindow", "positive number of days", "90", "Most-recent filtered days in the current period."),
      option("priorWindow", "positive number of days", "90", "Days immediately before the current period used for comparison.")
    ]),
    "activity-rings": doc("Apple-style Move, Exercise, and Stand rings. Single-day windows render one large ring set; multi-day windows render small multiples.", "activity.activeCalories, exerciseMinutes, and standHours.", [
      option("moveGoal", "calories", "500", "Target for the red Move ring."),
      option("exerciseGoal", "minutes", "30", "Target for the green Exercise ring."),
      option("standGoal", "hours", "12", "Target for the blue Stand ring.")
    ]),
    "activity-heatmap": doc("GitHub-style activity calendar shaded relative to the maximum value in the selected window.", "Daily activity summaries.", [option("metric", "steps, calories, distance", "steps", "Chooses the daily activity value. Calories uses active calories; distance uses walking/running kilometers.")]),
    "bar-chart": doc("Daily metric bars with a highlighted latest day, KPI header, optional average line, and optional goal line.", "Daily activity or sleep metric summaries.", [
      option("metric", "steps, activeCalories, exerciseMinutes, distance, sleepHours, flightsClimbed", "steps", "Selects the bar value, unit, and label."),
      option("goal", "number", "none", "Draws a dashed goal line and expands the y-axis if needed."),
      option("showAverage", "true, false, 1, 0", "true", "Toggles the dashed average line.")
    ]),
    "step-spiral": doc("Radial step-count history. Older days sit toward the center and newer days spiral outward.", "Daily step counts.", []),
    "weekday-average": doc("Seven bars showing a metric average by weekday. Best with at least four weeks of data.", "Daily metrics with dates.", [
      option("metric", "steps, activeCalories, exerciseMinutes, sleepHours, heartRate, hrv", "steps", "Chooses the value to bucket by weekday."),
      option("weekStart", "monday, sunday", "monday", "Controls bar order and x-axis labels.")
    ]),
    "heart-range": doc("Daily heart-rate min-to-max capsules with an average dot and optional resting-heart-rate reference.", "Heart-rate aggregates.", [option("metric", "heart-rate, resting, walking", "heart-rate", "Heart-rate uses min/max/average; resting and walking render single-value capsules.")]),
    "heart-terrain": doc("Ridgeline/heatmap view of heart-rate samples over the day, with a daily-aggregate fallback.", "Timestamped heart samples or daily heart aggregates.", []),
    "hrv-trend": doc("Line chart of heart-rate variability using daily HRV or averaged HRV samples.", "heart.hrv or hrvSamples.", []),
    "breathing-wave": doc("Respiratory-rate wave chart for spotting breathing changes, illness signals, or recovery stress.", "Respiratory-rate samples or aggregates.", []),
    "oxygen-range": doc("Daily min/max capsules with average dots for blood oxygen or respiratory rate, including warning zones.", "Blood oxygen or respiratory-rate aggregates.", [option("metric", "blood-oxygen, respiratory-rate", "blood-oxygen", "Chooses SpO₂ percentage or breaths/minute data.")]),
    "oxygen-river": doc("Flowing SpO₂ sample band across the selected window with summary stats.", "Blood oxygen samples.", []),
    "vitals-rings": doc("Radial daily chart combining steps, active calories, and resting/average heart-rate context.", "Activity plus heart data.", []),
    "walking-symmetry": doc("Mobility view for walking speed and walking asymmetry trends.", "Walking speed and asymmetry mobility metrics.", []),
    "sleep-architecture": doc("Linear sleep-stage timeline with one row per night for exact stage timing.", "Sleep stage intervals.", []),
    "sleep-polar": doc("Polar clock view of sleep stages that highlights consistent bedtimes and wake times.", "Sleep stage intervals with timestamps.", []),
    "sleep-quality-bars": doc("Stacked nightly bars showing deep, core, REM, and awake time composition.", "Sleep stage totals.", []),
    "sleep-schedule": doc("Bedtime-to-wake bars against a sunset/night/sunrise backdrop with goal-based coloring.", "Sleep bedtime, wake time, and duration.", [
      option("sleepGoal", "hours", "8", "Sleep-duration goal used for the goal marker and bar coloring."),
      option("windowStart", "HH:MM", "18:00", "Start of the x-axis window on each night's date."),
      option("windowEnd", "HH:MM", "10:00", "End of the x-axis window on the next day.")
    ]),
    "mood-trend": doc("State of Mind / mood valence trend from -1 unpleasant to +1 pleasant, optionally overlaid with recovery context.", "HealthKit State of Mind entries, Health.md mood summaries, or mood frontmatter.", [option("showContext", "true, false", "true", "Draws sleep and exercise/workout context columns behind the mood trend.")]),
    "mood-calendar-heatmap": doc("Month-style calendar cells colored by average daily mood valence.", "State of Mind or mood entries with dates.", []),
    "mood-sleep-scatter": doc("Scatter plot connecting each day's mood valence with sleep duration; exercise adds a ring.", "Mood entries plus sleep duration; exercise is optional.", []),
    "mood-day-timeline": doc("One row per day with mood entries positioned by time of day and sleep spans behind them.", "Timestamped State of Mind entries.", [option("maxDays", "positive integer", "21", "Maximum number of recent days to render.")]),
    "mood-association-breakdown": doc("Horizontal bars for average valence by association such as Work, Fitness, Family, or Friends.", "State of Mind associations.", [
      option("limit", "positive integer", "10", "Maximum number of associations to show."),
      option("sort", "count, valence", "count", "Sorts by entry frequency or average valence.")
    ]),
    "mood-label-cloud": doc("Emotion labels sized by frequency and colored by average valence.", "State of Mind labels.", [option("limit", "positive integer", "28", "Maximum number of labels to render.")]),
    "mood-volatility": doc("Daily average mood line with bars for intraday mood range.", "One or more mood entries per day.", []),
    "mood-kind-split": doc("Separate trend lines for Daily Mood and Momentary Emotion entries.", "State of Mind entries with kind information.", []),
    "mood-circadian-clock": doc("24-hour radial clock showing mood entry timing and valence.", "Timestamped mood entries.", []),
    "mood-recovery-tile": doc("Composite recovery/mindset card combining latest mood with sleep, HRV, and exercise context.", "Mood plus optional sleep, heart, and activity data.", []),
    "mood-association-matrix": doc("Emotion label by association matrix where cells show average valence or entry counts.", "State of Mind labels and associations.", [
      option("metric", "valence, count", "valence", "Chooses whether cells show average mood valence or number of entries."),
      option("labels", "positive integer", "6", "Maximum label rows."),
      option("associations", "positive integer", "6", "Maximum association columns.")
    ]),
    "workout-log": doc("Timeline of workouts in the filtered window, with bars sized by duration and colored by workout type.", "Workout summaries.", []),
    "workout-heart-rate": doc("Heart-rate time series for one selected workout, including optional zone bands.", "Workout heart-rate series or detailed heart-rate zones.", [
      option("date", "YYYY-MM-DD", "most recent filtered workout day", "Selects a specific workout day inside the filtered range."),
      option("workout", "zero-based number", "0", "Selects which workout on that day to render."),
      option("maxHeartRate", "BPM", "plugin setting", "Enables and scales Z1-Z5 heart-rate zone bands for this block.")
    ]),
    "workout-zones": doc("Stacked heart-rate zone time for one selected workout.", "Detailed workout heart_rate_zones or samples plus max HR.", [
      option("date", "YYYY-MM-DD", "most recent filtered workout day", "Selects a specific workout day."),
      option("workout", "zero-based number", "0", "Selects which workout on that day to render."),
      option("maxHeartRate", "BPM", "plugin setting", "Used when zones must be derived from heart-rate samples.")
    ]),
    "workout-trends": doc("Small-multiple workout trends for duration, distance, calories, average heart rate, and average power.", "Workout history.", [option("metric", "all, duration, distance, calories, hr_avg, power_avg", "all", "Chooses all trend panels or one focused metric.")]),
    "workout-map": doc("GPS route map for one outdoor workout, with Leaflet tiles when enabled and a canvas fallback otherwise.", "Workout route coordinates; heart-rate samples optional for HR coloring.", [
      option("date", "YYYY-MM-DD", "most recent filtered workout day", "Selects a specific workout day inside the filtered range."),
      option("workout", "zero-based number", "0", "Selects which workout on that day to render."),
      option("colorBy", "speed, hr", "speed", "Colors route segments by speed or nearest heart-rate sample."),
      option("height", "pixels", "360", "Map height."),
      option("width", "pixels", "800", "Canvas fallback width; Leaflet mode stretches to the note width.")
    ]),
    "workout-intervals": doc("HTML table for detailed workout laps and splits exported by Health.md.", "Detailed workout laps or splits.", [
      option("date", "YYYY-MM-DD", "most recent filtered workout day", "Selects a specific workout day."),
      option("workout", "zero-based number", "0", "Selects which workout on that day to render."),
      option("kind", "auto, laps, splits", "auto", "Chooses which interval tables to show.")
    ]),
    "medication-overview": doc("Full medication dashboard with inventory, adherence summary, per-medication status, trend bars, and recent dose events.", "Schema v2 medication details, dose events, or count summaries.", [
      option("trend", "auto, daily, weekly, monthly", "auto", "Groups adherence trend bars. Auto picks daily, weekly, or monthly from the range length."),
      option("limit", "positive integer", "12", "Maximum number of recent dose events to show.")
    ]),
    "medication-inventory": doc("Inventory totals and active/archived medication rows.", "Medication details or legacy medication lists.", []),
    "medication-adherence-summary": doc("Taken, skipped, and other dose-status rollup with adherence rate.", "Medication dose counts or dose events.", []),
    "medication-dose-status": doc("Per-medication dose status rows with adherence bars.", "Medication details plus dose events.", []),
    "medication-adherence-trend": doc("Daily, weekly, or monthly medication adherence trend columns.", "Medication dose counts or dose events.", [option("trend", "auto, daily, weekly, monthly", "auto", "Groups adherence trend bars.")]),
    "medication-recent-dose-events": doc("Recent dose-event table for medication logging review.", "Medication dose events.", [option("limit", "positive integer", "12", "Maximum number of recent dose events to show.")])
  };

  var permissionGroups = {
    Overview: "Depends on the chosen metric: Step Count, Active Energy, Heart Rate, HRV, Blood Oxygen, Respiratory Rate, Sleep Analysis, Distance Walking + Running, and any vitals shown in the summary.",
    Activity: "Step Count, Active Energy, Exercise Time, Stand Time / Stand Hours, Distance Walking + Running, and Flights Climbed where used.",
    Heart: "Heart Rate, Resting Heart Rate, Walking Heart Rate Average, Heart Rate Variability (SDNN), and VO₂ Max where used.",
    Sleep: "Sleep Analysis, including sleep stage samples when available.",
    Vitals: "Blood Oxygen and Respiratory Rate. Some combined vital views also benefit from Step Count, Active Energy, and Heart Rate.",
    Mobility: "Walking Speed and Walking Asymmetry. Additional mobility exports may include Step Length, Double Support, Stair Speed, Six-Minute Walk, and Walking Steadiness.",
    Mindfulness: "State of Mind (iOS 18+) for mood entries. Context overlays may also need Sleep Analysis, Exercise Time / Workouts, and HRV.",
    Workouts: "Workouts. Detailed workout charts may also need Heart Rate, Workout Routes, Active Energy, and distance types such as Walking + Running or Cycling.",
    Medications: "Medication export must be enabled separately in Health.md, then selected in Apple's per-medication authorization sheet (iOS 26+). Uses Medications and Medication Dose Events."
  };

  var visualizationPermissions = {
    "intro-stats": "Step Count, Active Energy, Distance Walking + Running, Heart Rate, Sleep Analysis, Blood Oxygen, Respiratory Rate, and any other vitals included in the export.",
    "summary-card": "The selected metric's Health permission: Heart Rate, Step Count, Sleep Analysis, Active Energy, HRV, Blood Oxygen, or Respiratory Rate.",
    "trend-tile": "The selected metric's Health permission: Resting Heart Rate, HRV, Step Count, VO₂ Max, Walking Speed, Sleep Analysis, or Active Energy.",
    "activity-rings": "Active Energy, Exercise Time, Stand Time, and Stand Hours.",
    "activity-heatmap": "Step Count by default; Active Energy for calories; Distance Walking + Running for distance.",
    "bar-chart": "Depends on metric: Step Count, Active Energy, Exercise Time, Distance Walking + Running, Sleep Analysis, or Flights Climbed.",
    "step-spiral": "Step Count.",
    "weekday-average": "Depends on metric: Step Count, Active Energy, Exercise Time, Sleep Analysis, Heart Rate, or HRV.",
    "heart-range": "Heart Rate plus Resting Heart Rate or Walking Heart Rate Average when those metrics are selected.",
    "heart-terrain": "Heart Rate samples; daily heart aggregates are exported when sample-level data is unavailable.",
    "hrv-trend": "Heart Rate Variability (SDNN).",
    "breathing-wave": "Respiratory Rate.",
    "oxygen-range": "Blood Oxygen for SpO₂ mode; Respiratory Rate for respiratory mode.",
    "oxygen-river": "Blood Oxygen samples.",
    "vitals-rings": "Step Count, Active Energy, Heart Rate, Resting Heart Rate, Blood Oxygen, and Respiratory Rate where available.",
    "walking-symmetry": "Walking Speed and Walking Asymmetry.",
    "sleep-architecture": "Sleep Analysis with stage samples.",
    "sleep-polar": "Sleep Analysis with stage samples.",
    "sleep-quality-bars": "Sleep Analysis with stage samples.",
    "sleep-schedule": "Sleep Analysis.",
    "mood-trend": "State of Mind (iOS 18+). Enable Sleep Analysis, Exercise Time / Workouts, and HRV for context overlays.",
    "mood-sleep-scatter": "State of Mind and Sleep Analysis; Exercise Time / Workouts adds exercise context.",
    "mood-recovery-tile": "State of Mind plus Sleep Analysis, HRV, and Exercise Time / Workouts for the recovery context.",
    "workout-heart-rate": "Workouts and Heart Rate. Max heart-rate zones use the app setting when HealthKit does not provide zones.",
    "workout-zones": "Workouts and Heart Rate, or detailed workout heart-rate-zone data when present.",
    "workout-trends": "Workouts plus related workout metrics such as Distance, Active Energy, Heart Rate, and Power when available.",
    "workout-map": "Workouts and Workout Routes. Heart Rate is also needed when colorBy is hr.",
    "workout-intervals": "Workouts with lap or split detail in the Health.md export.",
    "medication-overview": permissionGroups.Medications,
    "medication-inventory": permissionGroups.Medications,
    "medication-adherence-summary": permissionGroups.Medications,
    "medication-dose-status": permissionGroups.Medications,
    "medication-adherence-trend": permissionGroups.Medications,
    "medication-recent-dose-events": permissionGroups.Medications
  };

  function viz(id, label, category, renderer, description, tags, config) {
    return { id: id, label: label, category: category, renderer: renderer, description: description, tags: tags || [], config: config };
  }

  function option(name, values, defaultValue, effect) {
    return { name: name, values: values, defaultValue: defaultValue, effect: effect };
  }

  function palette(id, label, description, colors) {
    return { id: id, label: label, description: description, colors: colors };
  }

  function doc(description, dataNeeded, options) {
    return { description: description, dataNeeded: dataNeeded, options: options || [] };
  }

  function installObsidianDomShims() {
    window.activeWindow = window;
    window.activeDocument = document;

    if (!HTMLElement.prototype.empty) {
      HTMLElement.prototype.empty = function () { this.textContent = ""; };
    }
    if (!HTMLElement.prototype.addClass) {
      HTMLElement.prototype.addClass = function (className) {
        String(className || "").split(/\s+/).filter(Boolean).forEach(function (name) { this.classList.add(name); }, this);
      };
    }
    if (!HTMLElement.prototype.removeClass) {
      HTMLElement.prototype.removeClass = function (className) {
        String(className || "").split(/\s+/).filter(Boolean).forEach(function (name) { this.classList.remove(name); }, this);
      };
    }
    if (!HTMLElement.prototype.createDiv) {
      HTMLElement.prototype.createDiv = function (options) {
        var el = document.createElement("div");
        applyCreateOptions(el, options);
        this.appendChild(el);
        return el;
      };
    }
    if (!HTMLElement.prototype.createSpan) {
      HTMLElement.prototype.createSpan = function (options) {
        var el = document.createElement("span");
        applyCreateOptions(el, options);
        this.appendChild(el);
        return el;
      };
    }
    if (!HTMLElement.prototype.createEl) {
      HTMLElement.prototype.createEl = function (tag, options) {
        var el = document.createElement(tag);
        applyCreateOptions(el, options);
        this.appendChild(el);
        return el;
      };
    }
  }

  function applyCreateOptions(el, options) {
    if (!options) return;
    if (typeof options === "string") {
      el.className = options;
      return;
    }
    if (options.cls) {
      if (Array.isArray(options.cls)) el.className = options.cls.join(" ");
      else el.className = options.cls;
    }
    if (options.text !== undefined) el.textContent = String(options.text);
    if (options.attr) {
      Object.keys(options.attr).forEach(function (key) {
        el.setAttribute(key, String(options.attr[key]));
      });
    }
  }

  function readState() {
    try {
      var parsed = JSON.parse(localStorage.getItem(storageKey) || "null");
      if (!parsed || typeof parsed !== "object") return;
      if (byId(visualizations, parsed.visualization)) state.visualization = parsed.visualization;
      if (isColorScheme(parsed.colorScheme)) state.colorScheme = parsed.colorScheme;
      if (parsed.dataFilter === "all" || categoryLabels[parsed.dataFilter]) state.dataFilter = parsed.dataFilter;
      if (parsed.parameterOverrides && typeof parsed.parameterOverrides === "object") state.parameterOverrides = parsed.parameterOverrides;
    } catch (_error) {
      // Ignore invalid persisted state.
    }
  }

  function writeState() {
    try {
      localStorage.setItem(storageKey, JSON.stringify(state));
    } catch (_error) {
      // Ignore private-mode storage failures.
    }
  }

  function invertMap(map) {
    var inverse = {};
    Object.keys(map).forEach(function (key) { inverse[map[key]] = key; });
    return inverse;
  }

  var dataFiltersBySlug = invertMap(dataFilterSlugs);
  var colorSchemesBySlug = invertMap(colorSchemeSlugs);

  function normalizePathSegment(value) {
    return String(value || "").toLowerCase().replace(/\/+$/g, "");
  }

  function readUrlState() {
    var path = window.location.pathname.replace(/\/+$/g, "");
    var segments = path.split("/").filter(Boolean);
    var parsed = {};
    var hasSelection = false;

    if (segments[0] === "visualizations" && segments.length >= 3) {
      var filter = dataFiltersBySlug[normalizePathSegment(segments[1])];
      var visualization = normalizePathSegment(segments[2]);
      var colorScheme = colorSchemesBySlug[normalizePathSegment(segments[3] || "")];

      if (filter && (filter === "all" || categoryLabels[filter])) {
        parsed.dataFilter = filter;
        hasSelection = true;
      }
      if (byId(visualizations, visualization)) {
        parsed.visualization = visualization;
        hasSelection = true;
      }
      if (colorScheme && isColorScheme(colorScheme)) {
        parsed.colorScheme = colorScheme;
        hasSelection = true;
      }
    }

    var params = new URLSearchParams(window.location.search);
    var queryVisualization = normalizePathSegment(params.get("visualization") || params.get("viz") || "");
    var queryFilterRaw = params.get("data") || params.get("filter") || "";
    var queryFilter = dataFiltersBySlug[normalizePathSegment(queryFilterRaw)] || queryFilterRaw;
    var queryColorRaw = normalizePathSegment(params.get("colors") || params.get("colorScheme") || "");
    var queryColorScheme = colorSchemesBySlug[queryColorRaw] || queryColorRaw;
    if (byId(visualizations, queryVisualization)) {
      parsed.visualization = queryVisualization;
      hasSelection = true;
    }
    if (queryFilter === "all" || categoryLabels[queryFilter]) {
      parsed.dataFilter = queryFilter;
      hasSelection = true;
    }
    if (isColorScheme(queryColorScheme)) {
      parsed.colorScheme = queryColorScheme;
      hasSelection = true;
    }

    return hasSelection ? parsed : null;
  }

  function applyUrlState(parsed) {
    if (!parsed) return;
    if (parsed.visualization) state.visualization = parsed.visualization;
    if (parsed.colorScheme) state.colorScheme = parsed.colorScheme;
    if (parsed.dataFilter) state.dataFilter = parsed.dataFilter;
  }

  function visualizationUrl(viz) {
    var filterSlug = dataFilterSlugs[state.dataFilter] || dataFilterSlugs[viz.category] || dataFilterSlugs.all;
    var colorSlug = colorSchemeSlugs[state.colorScheme] || colorSchemeSlugs.theme;
    return "/visualizations/" + filterSlug + "/" + viz.id + "/" + colorSlug + "/";
  }

  function absoluteVisualizationUrl(viz) {
    return window.location.origin + visualizationUrl(viz);
  }

  function syncUrl(viz, shouldPush) {
    if (!window.history || !window.history.replaceState) return;
    var path = visualizationUrl(viz);
    if (window.location.pathname === path && !window.location.search && !window.location.hash) return;
    var method = shouldPush && window.history.pushState ? "pushState" : "replaceState";
    window.history[method]({ healthMdVisualizationState: true }, "", path);
  }

  function pageTitle(viz) {
    return viz.label + " — Health.md " + (categoryLabels[viz.category] || viz.category) + " Visualization";
  }

  function pageDescription(viz) {
    var themeDescription = state.colorScheme === "theme" ? "current theme" : "the " + colorSchemeLabel(state.colorScheme) + " theme";
    return viz.description + " Copy the Obsidian health-viz block, inspect required Apple Health permissions, and share this exact " + (categoryLabels[state.dataFilter] || state.dataFilter) + " preview with " + themeDescription + ".";
  }

  function setMeta(selector, value) {
    var el = document.head.querySelector(selector);
    if (el) el.setAttribute("content", value);
  }

  function updatePageMetadata(viz) {
    var title = pageTitle(viz);
    var description = pageDescription(viz);
    var url = absoluteVisualizationUrl(viz);
    document.title = title;
    setMeta('meta[name="description"]', description);
    setMeta('meta[property="og:title"]', title);
    setMeta('meta[property="og:description"]', description);
    setMeta('meta[property="og:url"]', url);
    setMeta('meta[name="twitter:title"]', title);
    setMeta('meta[name="twitter:description"]', description);
    var canonical = document.head.querySelector('link[rel="canonical"]');
    if (canonical) canonical.setAttribute("href", url);
  }

  function byId(items, id) {
    return items.filter(function (item) { return item.id === id; })[0] || null;
  }

  function currentVisualization() {
    var available = listedVisualizations();
    return byId(available, state.visualization) || available[0] || visualizations[0];
  }

  function pluginApi() {
    return window.HealthMdPluginVisualizations || { renderers: {}, htmlRenderers: {}, colorSchemes: {} };
  }

  function isColorScheme(value) {
    return value === "theme" || !!pluginApi().colorSchemes[value];
  }

  function colorSchemeOption(value) {
    return colorSchemeOptions.filter(function (item) { return item.id === value; })[0] || colorSchemeOptions[0];
  }

  function colorSchemeLabel(value) {
    var option = colorSchemeOption(value);
    return option ? option.label : value;
  }

  function syncColorSchemeButtons() {
    var picker = app && app.querySelector("[data-viz-theme-options]");
    var label = app && app.querySelector("[data-viz-theme-label]");
    if (label) label.textContent = colorSchemeLabel(state.colorScheme);
    if (!picker) return;
    Array.prototype.forEach.call(picker.querySelectorAll("[data-viz-color-option]"), function (button) {
      var selected = button.value === state.colorScheme;
      button.classList.toggle("is-selected", selected);
      button.setAttribute("aria-pressed", selected ? "true" : "false");
    });
  }

  function renderColorSchemeButtons() {
    var picker = app.querySelector("[data-viz-theme-options]");
    if (!picker) return;
    if (!picker.children.length) {
      colorSchemeOptions.forEach(function (option) {
        var button = document.createElement("button");
        button.type = "button";
        button.className = "theme-palette-button";
        button.value = option.id;
        button.setAttribute("data-viz-color-option", option.id);
        button.setAttribute("aria-label", option.label + " theme. " + option.description);
        button.setAttribute("title", option.label + " — " + option.description);
        option.colors.forEach(function (color, index) {
          button.style.setProperty(["--palette-accent", "--palette-secondary", "--palette-heart"][index], color);
        });
        var swatch = document.createElement("span");
        swatch.className = "theme-palette-swatch";
        swatch.setAttribute("aria-hidden", "true");
        swatch.appendChild(document.createElement("span"));
        swatch.appendChild(document.createElement("span"));
        swatch.appendChild(document.createElement("span"));
        var label = document.createElement("span");
        label.className = "theme-palette-label";
        label.textContent = option.label;
        button.appendChild(swatch);
        button.appendChild(label);
        picker.appendChild(button);
      });
    }
    syncColorSchemeButtons();
  }

  function systemPrefersDark() {
    return !!(window.matchMedia && window.matchMedia("(prefers-color-scheme: dark)").matches);
  }

  function websiteThemeMode() {
    var docTheme = document.documentElement.getAttribute("data-theme");
    if (docTheme === "dark" || docTheme === "light") return docTheme;
    return systemPrefersDark() ? "dark" : "light";
  }

  function effectiveThemeMode() {
    return state.themeMode === "auto" ? websiteThemeMode() : state.themeMode;
  }

  function isDarkMode() {
    return effectiveThemeMode() === "dark";
  }

  function cssVar(name, fallback) {
    var value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return value || fallback;
  }

  function syncObsidianThemeClass(isDark) {
    document.body.classList.toggle("theme-dark", isDark);
    document.body.classList.toggle("theme-light", !isDark);
    document.body.style.setProperty("--background-primary", cssVar("--color-background-100", isDark ? "#000000" : "#ffffff"));
    document.body.style.setProperty("--background-secondary", cssVar("--color-background-200", isDark ? "#0a0a0a" : "#fafafa"));
    document.body.style.setProperty("--background-modifier-border", cssVar("--color-gray-alpha-300", isDark ? "#ffffff21" : "#0000001a"));
    document.body.style.setProperty("--text-normal", cssVar("--color-primary", isDark ? "#ededed" : "#171717"));
    document.body.style.setProperty("--text-muted", cssVar("--color-secondary", isDark ? "#a0a0a0" : "#4d4d4d"));
    document.body.style.setProperty("--text-faint", cssVar("--color-gray-alpha-600", isDark ? "#ffffff82" : "#0000003d"));
    document.body.style.setProperty("--interactive-accent", cssVar("--color-tertiary", isDark ? "#a37dbd" : "#8a66aa"));
    document.body.style.setProperty("--color-accent", cssVar("--color-tertiary", isDark ? "#a37dbd" : "#8a66aa"));
    document.body.style.setProperty("--text-accent", cssVar("--color-teal-700", isDark ? "#00aa95" : "#00ac96"));
    document.body.style.setProperty("--interactive-accent-hover", cssVar("--color-teal-700", isDark ? "#00aa95" : "#00ac96"));
  }

  function pluginSettings() {
    return {
      dataFolder: "",
      filePattern: "",
      dataFormat: "auto",
      dataFolderGranularity: "flat",
      dataFolderCustomPathTemplate: "",
      theme: "auto",
      defaultWidth: 760,
      defaultHeight: 360,
      colorScheme: state.colorScheme,
      colorAccent: cssVar("--color-tertiary", "#8a66aa"),
      colorSecondary: cssVar("--color-teal-700", "#00ac96"),
      colorHeart: cssVar("--color-red-800", "#ea001d"),
      colorSleepDeep: cssVar("--color-purple-1000", "#2d1f4f"),
      colorSleepRem: cssVar("--color-purple-700", "#8a66aa"),
      colorSleepCore: cssVar("--color-teal-700", "#00ac96"),
      colorSleepAwake: cssVar("--color-blue-700", "#006bff"),
      maxHeartRate: 190,
      dataPointClickAction: "pin",
      mapTilesEnabled: false,
      mapTileUrl: "",
      mapTileAttribution: ""
    };
  }

  function fallbackTheme(isDark) {
    return {
      bg: isDark ? "#0a0a0f" : "#ffffff",
      fg: isDark ? "#e0e0e0" : "#1a1a1a",
      muted: isDark ? "#555555" : "#999999",
      isDark: isDark,
      colors: {
        accent: cssVar("--color-tertiary", "#8a66aa"),
        secondary: cssVar("--color-teal-700", "#00ac96"),
        heart: cssVar("--color-red-800", "#ea001d"),
        sleep: {
          deep: cssVar("--color-purple-1000", "#2d1f4f"),
          rem: cssVar("--color-purple-700", "#8a66aa"),
          core: cssVar("--color-teal-700", "#00ac96"),
          awake: cssVar("--color-blue-700", "#006bff")
        }
      },
      maxHeartRate: 190,
      mapTilesEnabled: false,
      mapTileUrl: "",
      mapTileAttribution: ""
    };
  }

  function resolvedTheme(config) {
    var dark = isDarkMode();
    syncObsidianThemeClass(dark);
    var api = pluginApi();
    if (typeof api.resolveTheme === "function") {
      return api.resolveTheme(pluginSettings(), config || { theme: state.themeMode, colorScheme: state.colorScheme });
    }
    return fallbackTheme(dark);
  }

  function parseDate(value) {
    return new Date(value + "T00:00:00");
  }

  function addDays(date, amount) {
    var next = new Date(date);
    next.setDate(next.getDate() + amount);
    return next;
  }

  function toIsoDate(date) {
    return date.toISOString().slice(0, 10);
  }

  function filteredData(config) {
    var data = sampleData.slice();
    var from = config.from;
    var to = config.to;
    if (config.last && to) {
      from = toIsoDate(addDays(parseDate(to), -(Number(config.last) - 1)));
    }
    if (from) data = data.filter(function (day) { return day.date >= from; });
    if (to) data = data.filter(function (day) { return day.date <= to; });
    return data;
  }

  function setupCanvas(canvas, width, height) {
    var dpr = window.devicePixelRatio || 1;
    canvas.width = Math.round(width * dpr);
    canvas.height = Math.round(height * dpr);
    canvas.style.width = width + "px";
    canvas.style.height = height + "px";
    var ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    return ctx;
  }

  function escapeHtml(value) {
    return String(value).replace(/[&<>"']/g, function (char) {
      return { "&": "&amp;", "<": "&lt;", ">": "&gt;", "\"": "&quot;", "'": "&#39;" }[char];
    });
  }

  var previewRegions = [];
  var previewPinned = null;
  var customSelects = [];
  var customSelectId = 0;

  function hitTest(region, x, y) {
    if (region.shape === "rect") return x >= region.x && x <= region.x + region.w && y >= region.y && y <= region.y + region.h;
    if (region.shape === "circle") {
      var dx = x - region.cx;
      var dy = y - region.cy;
      return dx * dx + dy * dy <= region.r * region.r;
    }
    if (region.shape === "sector") {
      var sx = x - region.cx;
      var sy = y - region.cy;
      var dist = Math.sqrt(sx * sx + sy * sy);
      if (dist < region.r0 || dist > region.r1) return false;
      if (region.a1 - region.a0 >= Math.PI * 2 - 0.001) return true;
      var angle = Math.atan2(sy, sx);
      var a0 = region.a0;
      var a1 = region.a1;
      while (a1 <= a0) a1 += Math.PI * 2;
      while (angle < a0) angle += Math.PI * 2;
      return angle <= a1;
    }
    return false;
  }

  function findRegion(regions, x, y) {
    for (var i = regions.length - 1; i >= 0; i--) {
      if (hitTest(regions[i], x, y)) return regions[i];
    }
    return null;
  }

  function ensurePreviewTooltip(shell) {
    var tooltip = shell.querySelector("[data-viz-tooltip]");
    if (!tooltip) {
      tooltip = document.createElement("div");
      tooltip.className = "health-md-tooltip is-hidden";
      tooltip.setAttribute("data-viz-tooltip", "");
      tooltip.setAttribute("role", "tooltip");
      shell.appendChild(tooltip);
    }
    return tooltip;
  }

  function renderTooltipContent(tooltip, region) {
    tooltip.empty();
    tooltip.createDiv({ cls: "health-md-tooltip-title", text: region.title || "Data point" });
    var body = tooltip.createDiv({ cls: "health-md-tooltip-details" });
    (region.details || []).forEach(function (detail) {
      var row = body.createDiv({ cls: "health-md-tooltip-row" });
      row.createSpan({ cls: "health-md-tooltip-label", text: detail.label });
      row.createSpan({ cls: "health-md-tooltip-value", text: detail.value });
    });
  }

  function hidePreviewTooltip(shell) {
    var tooltip = shell && shell.querySelector("[data-viz-tooltip]");
    if (tooltip) tooltip.classList.add("is-hidden");
  }

  function placeTooltip(shell, canvas, tooltip, x, y) {
    tooltip.classList.remove("is-hidden");
    var tx = canvas.offsetLeft + x + 14;
    var ty = canvas.offsetTop + y + 14;
    var tw = tooltip.offsetWidth;
    var th = tooltip.offsetHeight;
    var maxX = shell.scrollLeft + shell.clientWidth;
    var maxY = shell.scrollTop + shell.clientHeight;
    if (tx + tw > maxX) tx = canvas.offsetLeft + x - 14 - tw;
    if (ty + th > maxY) ty = canvas.offsetTop + y - 14 - th;
    if (tx < shell.scrollLeft) tx = shell.scrollLeft;
    if (ty < shell.scrollTop) ty = shell.scrollTop;
    tooltip.style.left = tx + "px";
    tooltip.style.top = ty + "px";
  }

  function getCanvasPoint(event, canvas) {
    var rect = canvas.getBoundingClientRect();
    var logicalWidth = parseFloat(canvas.style.width) || rect.width || 1;
    var logicalHeight = parseFloat(canvas.style.height) || rect.height || 1;
    var displayX = event.clientX - rect.left;
    var displayY = event.clientY - rect.top;
    return {
      x: displayX * (logicalWidth / (rect.width || logicalWidth)),
      y: displayY * (logicalHeight / (rect.height || logicalHeight)),
      displayX: displayX,
      displayY: displayY
    };
  }

  function bindCanvasInteractivity(canvas, shell) {
    if (canvas.__healthMdVizInteractivityBound) return;
    canvas.__healthMdVizInteractivityBound = true;

    canvas.addEventListener("mousemove", function (event) {
      if (previewPinned) return;
      var point = getCanvasPoint(event, canvas);
      var x = point.x;
      var y = point.y;
      var region = findRegion(previewRegions, x, y);
      var tooltip = ensurePreviewTooltip(shell);
      if (region) {
        canvas.classList.add("health-md-canvas-pointer");
        renderTooltipContent(tooltip, region);
        placeTooltip(shell, canvas, tooltip, point.displayX, point.displayY);
      } else {
        canvas.classList.remove("health-md-canvas-pointer");
        tooltip.classList.add("is-hidden");
      }
    });

    canvas.addEventListener("mouseleave", function () {
      if (previewPinned) return;
      canvas.classList.remove("health-md-canvas-pointer");
      hidePreviewTooltip(shell);
    });

    canvas.addEventListener("click", function (event) {
      var point = getCanvasPoint(event, canvas);
      var x = point.x;
      var y = point.y;
      var region = findRegion(previewRegions, x, y);
      var tooltip = ensurePreviewTooltip(shell);
      if (region) {
        previewPinned = region;
        renderTooltipContent(tooltip, region);
        placeTooltip(shell, canvas, tooltip, point.displayX, point.displayY);
      } else if (previewPinned) {
        previewPinned = null;
        tooltip.classList.add("is-hidden");
      }
    });
  }

  function rendererForItem(item) {
    var api = pluginApi();
    return item.renderer === "html" ? api.htmlRenderers[item.id] : api.renderers[item.id];
  }

  function listedVisualizations() {
    return visualizations.filter(function (item) { return !!rendererForItem(item); });
  }

  function filteredVisualizations() {
    return listedVisualizations().filter(function (item) {
      if (state.dataFilter !== "all" && item.category !== state.dataFilter) return false;
      return true;
    });
  }

  function ensureSelectionInFilter() {
    var filtered = filteredVisualizations();
    if (!filtered.length) return;
    if (!byId(filtered, state.visualization)) state.visualization = filtered[0].id;
  }

  function renderVisualizationSelect() {
    var select = app.querySelector("[data-viz-select]");
    var filtered = filteredVisualizations();

    if (!filtered.length) {
      select.innerHTML = '<option value="">No visualizations available</option>';
      select.disabled = true;
      return;
    }

    select.disabled = false;
    select.innerHTML = filtered.map(function (item) {
      return '<option value="' + escapeHtml(item.id) + '">' + escapeHtml(item.label) + '</option>';
    }).join("");
    select.value = state.visualization;
  }

  function docsForVisualization(viz) {
    return visualizationDocs[viz.id] || doc(viz.description, "Matching Health.md data for this category.", []);
  }

  function visualizationOptions(viz) {
    var docs = docsForVisualization(viz);
    var specific = (docs.options || []).slice();
    var optionNames = {};
    specific.forEach(function (item) { optionNames[item.name] = true; });
    var common = commonVisualizationOptions.filter(function (item) {
      if (item.name === "type" || item.name === "theme" || item.name.indexOf("colorScheme") === 0) return false;
      if (!Object.prototype.hasOwnProperty.call(viz.config, item.name)) return false;
      return !optionNames[item.name];
    });
    return common.concat(specific);
  }

  function parameterOverridesFor(viz, create) {
    if (!state.parameterOverrides || typeof state.parameterOverrides !== "object") state.parameterOverrides = {};
    if (!state.parameterOverrides[viz.id] || typeof state.parameterOverrides[viz.id] !== "object") {
      if (!create) return {};
      state.parameterOverrides[viz.id] = {};
    }
    return state.parameterOverrides[viz.id];
  }

  function activeConfig(viz) {
    return Object.assign({}, viz.config, parameterOverridesFor(viz, false), {
      theme: state.themeMode,
      colorScheme: state.colorScheme
    });
  }

  function isLiteralDefault(value) {
    var text = String(value || "").trim();
    if (!text || text === "none" || text === "plugin setting") return false;
    if (/^most recent/i.test(text)) return false;
    return true;
  }

  function baseParameterValue(viz, option) {
    if (Object.prototype.hasOwnProperty.call(viz.config, option.name)) return viz.config[option.name];
    return isLiteralDefault(option.defaultValue) ? option.defaultValue : "";
  }

  function parameterControlValue(viz, option) {
    var overrides = parameterOverridesFor(viz, false);
    if (Object.prototype.hasOwnProperty.call(overrides, option.name)) return overrides[option.name];
    return baseParameterValue(viz, option);
  }

  function parameterChoices(option) {
    var values = String(option.values || "");
    if (values.indexOf(",") === -1) return null;
    if (/date|datetime|number of|positive|pixels|hours|calories|minutes|BPM|HH:MM|CSS|zero-based|setting|none/i.test(values)) return null;
    return values.split(",").map(function (value) { return value.trim(); }).filter(Boolean);
  }

  function parameterInputType(option) {
    var values = String(option.values || "");
    if (/YYYY-MM-DD|date/i.test(values)) return "date";
    if (/HH:MM/i.test(values)) return "time";
    if (/number|positive|zero-based|pixels|hours|calories|minutes|BPM|integer/i.test(values)) return "number";
    return "text";
  }

  function numericStep(option) {
    return /hours/i.test(option.values || "") ? "0.1" : "1";
  }

  function coerceParameterValue(option, rawValue) {
    if (parameterInputType(option) === "number" && rawValue !== "") return Number(rawValue);
    return rawValue;
  }

  function sameParameterValue(left, right) {
    return String(left) === String(right);
  }

  function parameterDescription(option) {
    var pieces = [];
    if (option.defaultValue && String(option.defaultValue) !== "none") pieces.push("Default: " + option.defaultValue + ".");
    if (option.effect) pieces.push(option.effect);
    return pieces.join(" ");
  }

  function parameterLabel(name) {
    return String(name || "").replace(/([a-z])([A-Z])/g, "$1 $2").replace(/[-_]+/g, " ");
  }

  function renderParameterControls(viz) {
    var panel = app.querySelector("[data-viz-parameter-panel]");
    var controls = app.querySelector("[data-viz-parameter-controls]");
    if (!panel || !controls) return;
    var options = visualizationOptions(viz);
    if (!options.length) {
      panel.hidden = true;
      controls.empty();
      return;
    }

    panel.hidden = false;
    controls.innerHTML = options.map(function (option) {
      var id = "viz-param-" + viz.id + "-" + option.name.replace(/[^a-z0-9_-]/gi, "-");
      var value = parameterControlValue(viz, option);
      var description = parameterDescription(option);
      var choices = parameterChoices(option);
      var field;
      if (choices && choices.length) {
        field = "<select id=\"" + escapeHtml(id) + "\" data-viz-param=\"" + escapeHtml(option.name) + "\">" + choices.map(function (choice) {
          return "<option value=\"" + escapeHtml(choice) + "\"" + (sameParameterValue(choice, value) ? " selected" : "") + ">" + escapeHtml(choice) + "</option>";
        }).join("") + "</select>";
      } else {
        var type = parameterInputType(option);
        var attrs = type === "number" ? " step=\"" + numericStep(option) + "\"" : "";
        if (/positive/i.test(option.values || "")) attrs += " min=\"0\"";
        field = "<input id=\"" + escapeHtml(id) + "\" data-viz-param=\"" + escapeHtml(option.name) + "\" type=\"" + type + "\" value=\"" + escapeHtml(value) + "\" placeholder=\"" + escapeHtml(option.defaultValue || option.values || "") + "\"" + attrs + ">";
      }
      return "<label class=\"parameter-control\" for=\"" + escapeHtml(id) + "\">" +
        "<span class=\"parameter-control-label\"><span>" + escapeHtml(parameterLabel(option.name)) + "</span><code>" + escapeHtml(option.name) + "</code></span>" +
        field +
        "<small>" + escapeHtml(description || option.values || "Configures this visualization.") + "</small>" +
        "</label>";
    }).join("");
  }

  function updateParameterOverride(control) {
    var viz = currentVisualization();
    var option = visualizationOptions(viz).filter(function (item) { return item.name === control.getAttribute("data-viz-param"); })[0];
    if (!option) return;
    var overrides = parameterOverridesFor(viz, true);
    var rawValue = control.value;
    var baseValue = baseParameterValue(viz, option);
    if (rawValue === "" || sameParameterValue(rawValue, baseValue)) {
      delete overrides[option.name];
    } else {
      overrides[option.name] = coerceParameterValue(option, rawValue);
    }
    if (!Object.keys(overrides).length) delete state.parameterOverrides[viz.id];
  }

  function refreshParameterDrivenContent() {
    var viz = currentVisualization();
    app.querySelector("[data-viz-code]").textContent = renderCodeBlock(viz);
    updateIssueReportLink(viz);
    renderVisualizationDocs(viz);
    renderPreview(viz);
    writeState();
  }

  function scheduleParameterRender() {
    window.clearTimeout(parameterRenderTimer);
    parameterRenderTimer = window.setTimeout(refreshParameterDrivenContent, 160);
  }

  function resetCurrentParameters() {
    var viz = currentVisualization();
    if (state.parameterOverrides && state.parameterOverrides[viz.id]) delete state.parameterOverrides[viz.id];
    render({ skipUrl: true });
  }

  function renderCodeBlock(viz) {
    var config = activeConfig(viz);
    var order = ["type", "metric", "to", "from", "last", "date", "workout", "height", "width", "theme", "colorScheme", "goal", "showAverage", "moveGoal", "exerciseGoal", "standGoal", "sleepGoal", "windowStart", "windowEnd", "weekStart", "compareWindow", "currentWindow", "priorWindow", "trend", "limit", "maxDays", "sort", "labels", "associations", "kind", "maxHeartRate", "mode", "colorBy"];
    var keys = order.filter(function (key) { return config[key] !== undefined; });
    Object.keys(config).sort().forEach(function (key) {
      if (keys.indexOf(key) === -1 && config[key] !== undefined) keys.push(key);
    });
    var lines = ["```health-viz"];
    keys.forEach(function (key) {
      lines.push(key + ": " + config[key]);
    });
    lines.push("```");
    return lines.join("\n");
  }

  function issueReportBody(viz) {
    return [
      "Hi Cody,",
      "",
      "I'm seeing an issue with this visualization:",
      "",
      "What happened:",
      "",
      "What I expected:",
      "",
      "Steps to reproduce:",
      "1.",
      "2.",
      "3.",
      "",
      "---",
      "Visualization metadata",
      "Page: " + window.location.href,
      "Visualization: " + viz.label + " (" + viz.id + ")",
      "Category: " + (categoryLabels[viz.category] || viz.category),
      "Renderer: " + viz.renderer,
      "Data filter: " + (categoryLabels[state.dataFilter] || state.dataFilter),
      "Visualization theme: " + colorSchemeLabel(state.colorScheme) + " (" + state.colorScheme + ")",
      "Theme mode: " + state.themeMode + " (effective: " + effectiveThemeMode() + ")",
      "Viewport: " + window.innerWidth + "x" + window.innerHeight,
      "User agent: " + navigator.userAgent,
      "",
      "health-viz block:",
      renderCodeBlock(viz)
    ].join("\n");
  }

  function updateIssueReportLink(viz) {
    var link = app.querySelector("[data-report-issue]");
    if (!link) return;
    var subject = "Health.md visualization issue: " + viz.label + " (" + viz.id + ")";
    link.href = "mailto:cody@isolated.tech?subject=" + encodeURIComponent(subject) + "&body=" + encodeURIComponent(issueReportBody(viz));
    link.setAttribute("aria-label", "Report an issue with " + viz.label);
  }

  function optionRows(options) {
    return options.map(function (item) {
      return "<tr>" +
        "<th scope=\"row\"><code>" + escapeHtml(item.name) + "</code></th>" +
        "<td>" + escapeHtml(item.values) + "</td>" +
        "<td>" + escapeHtml(item.defaultValue) + "</td>" +
        "<td>" + escapeHtml(item.effect) + "</td>" +
        "</tr>";
    }).join("");
  }

  function optionsTable(options) {
    return "<div class=\"docs-table-wrap\"><table class=\"docs-options\">" +
      "<thead><tr><th>Option</th><th>Values</th><th>Default</th><th>Effect</th></tr></thead>" +
      "<tbody>" + optionRows(options) + "</tbody></table></div>";
  }

  function renderVisualizationDocs(viz) {
    var panel = app.querySelector("[data-viz-docs]");
    if (!panel) return;
    var docs = docsForVisualization(viz);
    var permissions = visualizationPermissions[viz.id] || permissionGroups[viz.category] || "Grant the matching Health data type in Health.md during HealthKit authorization.";
    var specificOptions = docs.options && docs.options.length ? optionsTable(docs.options) : "<p class=\"docs-empty\">No visualization-specific options. Use the common date, size, theme, and color options below to adapt this block.</p>";
    panel.innerHTML = "<div class=\"docs-header\">" +
      "<span class=\"eyebrow\">Obsidian plugin docs</span>" +
      "<h3>" + escapeHtml(viz.label) + " <code>" + escapeHtml(viz.id) + "</code></h3>" +
      "<p>" + escapeHtml(docs.description || viz.description) + "</p>" +
      "</div>" +
      "<div class=\"docs-meta\">" +
      "<div><span>HealthKit permissions</span><strong>" + escapeHtml(permissions) + "</strong></div>" +
      "<div><span>Category</span><strong>" + escapeHtml(categoryLabels[viz.category] || viz.category) + "</strong></div>" +
      "<div><span>Data needed</span><strong>" + escapeHtml(docs.dataNeeded) + "</strong></div>" +
      "</div>" +
      "<div class=\"docs-section\"><h4>Visualization options</h4>" + specificOptions + "</div>" +
      "<details class=\"docs-section docs-details\"><summary>Common <code>health-viz</code> block options</summary>" + optionsTable(commonVisualizationOptions) + "</details>" +
      "<div class=\"docs-section docs-code\"><div class=\"docs-code-header\"><h4>Copyable block for this preview</h4><button class=\"copy-icon-button\" type=\"button\" data-copy-block aria-label=\"Copy health-viz block\" title=\"Copy health-viz block\"><svg aria-hidden=\"true\" viewBox=\"0 0 24 24\" width=\"16\" height=\"16\"><path class=\"copy-glyph\" d=\"M8 7a3 3 0 0 1 3-3h6a3 3 0 0 1 3 3v6a3 3 0 0 1-3 3h-1v1a3 3 0 0 1-3 3H7a3 3 0 0 1-3-3v-6a3 3 0 0 1 3-3h1V7Zm2 1h3a3 3 0 0 1 3 3v3h1a1 1 0 0 0 1-1V7a1 1 0 0 0-1-1h-6a1 1 0 0 0-1 1v1Zm-3 2a1 1 0 0 0-1 1v6a1 1 0 0 0 1 1h6a1 1 0 0 0 1-1v-6a1 1 0 0 0-1-1H7Z\" fill=\"currentColor\"/><path class=\"check-glyph\" d=\"M9.55 16.6 5.3 12.35l1.4-1.4 2.85 2.85 7.75-7.75 1.4 1.4-9.15 9.15Z\" fill=\"currentColor\"/></svg><span class=\"copy-icon-label\">Copy</span></button></div><pre><code>" + escapeHtml(renderCodeBlock(viz)) + "</code></pre></div>";
  }

  function renderPreview(viz) {
    var renderer = rendererForItem(viz);
    var canvas = app.querySelector("[data-viz-canvas]");
    var html = app.querySelector("[data-viz-html]");
    var stats = app.querySelector("[data-viz-stats]");
    var error = app.querySelector("[data-render-error]");
    var shell = app.querySelector(".canvas-shell");
    var config = activeConfig(viz);
    var activeTheme = resolvedTheme(config);
    var width = Math.max(320, Math.min(960, shell.clientWidth - 48 || 960));
    var height = Number(config.height) || 360;

    error.hidden = true;
    canvas.hidden = viz.renderer === "html";
    html.hidden = viz.renderer !== "html";
    stats.hidden = viz.renderer === "html";
    stats.empty();
    html.empty();
    html.className = "html-preview";
    shell.classList.toggle("is-html-stage", viz.renderer === "html");
    previewRegions = [];
    previewPinned = null;
    canvas.classList.remove("health-md-canvas-pointer");
    hidePreviewTooltip(shell);
    bindCanvasInteractivity(canvas, shell);

    if (!renderer) {
      error.textContent = "Visualization missing. The Health.md plugin bundle did not expose “" + viz.id + "”.";
      error.hidden = false;
      canvas.hidden = true;
      html.hidden = true;
      return;
    }

    try {
      if (viz.renderer === "html") {
        html.style.minHeight = Math.max(180, height) + "px";
        renderer(filteredData(config), html, config, activeTheme);
        return;
      }
      var ctx = setupCanvas(canvas, width, height);
      renderer(ctx, filteredData(config), width, height, config, activeTheme, stats, { add: function (region) { previewRegions.push(region); } });
    } catch (err) {
      error.textContent = "Render failed. " + (err && err.message ? err.message : String(err));
      error.hidden = false;
      canvas.hidden = true;
      html.hidden = true;
      console.error(err);
    }
  }

  function render(options) {
    options = options || {};
    ensureSelectionInFilter();
    var viz = currentVisualization();
    if (!options.skipUrl) syncUrl(viz, options.pushUrl);
    updatePageMetadata(viz);
    renderVisualizationSelect();
    app.querySelector("[data-current-category]").textContent = categoryLabels[viz.category] || viz.category;
    app.querySelector("[data-current-title]").textContent = viz.label;
    app.querySelector("[data-current-description]").textContent = viz.description;
    app.querySelector("[data-viz-color-scheme]").value = state.colorScheme;
    app.querySelector("[data-viz-data-filter]").value = state.dataFilter;
    renderColorSchemeButtons();
    renderParameterControls(viz);
    syncCustomSelects();
    app.querySelector("[data-viz-code]").textContent = renderCodeBlock(viz);
    app.querySelector("[data-code-label]").textContent = viz.id;
    updateIssueReportLink(viz);
    renderVisualizationDocs(viz);
    renderPreview(viz);
    writeState();
  }

  function copyBlock(button) {
    var block = renderCodeBlock(currentVisualization());
    if (!navigator.clipboard || !button) return;
    navigator.clipboard.writeText(block).then(function () {
      var originalTitle = button.getAttribute("title") || "Copy health-viz block";
      button.classList.add("is-copied");
      button.setAttribute("aria-label", "Copied health-viz block");
      button.setAttribute("title", "Copied");
      window.setTimeout(function () {
        button.classList.remove("is-copied");
        button.setAttribute("aria-label", originalTitle);
        button.setAttribute("title", originalTitle);
      }, 1200);
    });
  }

  function selectLabelText(select) {
    var label = select.closest("label");
    if (!label) return select.getAttribute("aria-label") || "Choose option";
    var text = "";
    Array.prototype.forEach.call(label.childNodes, function (node) {
      if (node === select) return;
      if (node.nodeType === Node.TEXT_NODE) text += " " + node.textContent;
    });
    return text.replace(/\s+/g, " ").trim() || select.getAttribute("aria-label") || "Choose option";
  }

  function selectedOption(select) {
    return select.options[select.selectedIndex] || select.options[0] || null;
  }

  function optionButtons(controller) {
    return Array.prototype.slice.call(controller.list.querySelectorAll("[data-custom-select-option]"));
  }

  function closeCustomSelect(controller) {
    controller.root.classList.remove("is-open");
    controller.list.hidden = true;
    controller.button.setAttribute("aria-expanded", "false");
    app.querySelector(".floating-controls").classList.remove("has-open-custom-select");
  }

  function closeOtherCustomSelects(activeController) {
    customSelects.forEach(function (controller) {
      if (controller !== activeController) closeCustomSelect(controller);
    });
  }

  function focusCustomSelectOption(controller, index) {
    var buttons = optionButtons(controller).filter(function (button) { return !button.disabled; });
    if (!buttons.length) return;
    var safeIndex = Math.max(0, Math.min(index, buttons.length - 1));
    buttons[safeIndex].focus();
  }

  function focusSelectedCustomSelectOption(controller) {
    var buttons = optionButtons(controller).filter(function (button) { return !button.disabled; });
    var selectedIndex = buttons.findIndex(function (button) { return button.getAttribute("aria-selected") === "true"; });
    focusCustomSelectOption(controller, selectedIndex >= 0 ? selectedIndex : 0);
  }

  function openCustomSelect(controller, shouldFocusOption) {
    if (controller.button.disabled) return;
    closeOtherCustomSelects(controller);
    controller.root.classList.add("is-open");
    controller.list.hidden = false;
    controller.button.setAttribute("aria-expanded", "true");
    app.querySelector(".floating-controls").classList.add("has-open-custom-select");
    if (shouldFocusOption) window.setTimeout(function () { focusSelectedCustomSelectOption(controller); }, 0);
  }

  function toggleCustomSelect(controller) {
    if (controller.root.classList.contains("is-open")) closeCustomSelect(controller);
    else openCustomSelect(controller, false);
  }

  function chooseCustomSelectOption(controller, value) {
    if (controller.select.value !== value) {
      controller.select.value = value;
      controller.select.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
      syncCustomSelect(controller);
    }
    closeCustomSelect(controller);
    controller.button.focus();
  }

  function syncCustomSelect(controller) {
    var select = controller.select;
    var option = selectedOption(select);
    var label = option ? option.textContent : "No options";
    controller.button.textContent = label;
    controller.button.disabled = select.disabled;
    controller.button.setAttribute("aria-label", controller.label + ": " + label);
    controller.button.setAttribute("aria-disabled", select.disabled ? "true" : "false");
    controller.list.innerHTML = "";

    Array.prototype.forEach.call(select.options, function (item) {
      var button = document.createElement("button");
      button.type = "button";
      button.className = "custom-select-option";
      button.setAttribute("role", "option");
      button.setAttribute("data-custom-select-option", "");
      button.setAttribute("aria-selected", item.value === select.value ? "true" : "false");
      button.value = item.value;
      button.disabled = item.disabled;
      button.textContent = item.textContent;
      button.addEventListener("click", function (event) {
        // The native <select> lives inside the same <label> so screen readers still
        // have the original semantics. On iOS Safari, clicks inside a label can
        // also activate that hidden select after our custom option handler runs,
        // which opens a second native picker. Cancelling the button click keeps the
        // interaction on the custom list only.
        event.preventDefault();
        event.stopPropagation();
        chooseCustomSelectOption(controller, item.value);
      });
      controller.list.appendChild(button);
    });
  }

  function handleCustomSelectKeydown(controller, event) {
    var buttons = optionButtons(controller).filter(function (button) { return !button.disabled; });
    var currentIndex = buttons.indexOf(document.activeElement);
    if (event.key === "Escape") {
      event.preventDefault();
      closeCustomSelect(controller);
      controller.button.focus();
    } else if (event.key === "ArrowDown") {
      event.preventDefault();
      openCustomSelect(controller, false);
      focusCustomSelectOption(controller, currentIndex < 0 ? 0 : currentIndex + 1);
    } else if (event.key === "ArrowUp") {
      event.preventDefault();
      openCustomSelect(controller, false);
      focusCustomSelectOption(controller, currentIndex < 0 ? buttons.length - 1 : currentIndex - 1);
    } else if (event.key === "Home") {
      event.preventDefault();
      openCustomSelect(controller, false);
      focusCustomSelectOption(controller, 0);
    } else if (event.key === "End") {
      event.preventDefault();
      openCustomSelect(controller, false);
      focusCustomSelectOption(controller, buttons.length - 1);
    } else if ((event.key === "Enter" || event.key === " ") && document.activeElement !== controller.button) {
      event.preventDefault();
      chooseCustomSelectOption(controller, document.activeElement.value);
    } else if ((event.key === "Enter" || event.key === " ") && document.activeElement === controller.button) {
      event.preventDefault();
      openCustomSelect(controller, true);
    } else if (event.key === "Tab") {
      closeCustomSelect(controller);
    }
  }

  function enhanceSelect(select) {
    if (select.__healthMdCustomSelect) return select.__healthMdCustomSelect;

    var id = ++customSelectId;
    var root = document.createElement("div");
    var button = document.createElement("button");
    var list = document.createElement("div");
    var controller = {
      select: select,
      label: selectLabelText(select),
      root: root,
      button: button,
      list: list
    };

    root.className = "custom-select";
    button.type = "button";
    button.id = "custom-select-button-" + id;
    button.className = "custom-select-button";
    button.setAttribute("aria-haspopup", "listbox");
    button.setAttribute("aria-expanded", "false");
    button.setAttribute("aria-controls", "custom-select-list-" + id);
    list.id = "custom-select-list-" + id;
    list.className = "custom-select-list";
    list.hidden = true;
    list.setAttribute("role", "listbox");
    list.setAttribute("aria-labelledby", button.id);

    select.classList.add("custom-select-native");
    select.setAttribute("aria-hidden", "true");
    select.tabIndex = -1;
    select.after(root);
    root.appendChild(button);
    root.appendChild(list);

    root.addEventListener("click", function (event) {
      // Any click inside the custom control is still inside the wrapping label;
      // cancel it so the hidden native select is never label-activated.
      event.preventDefault();
      event.stopPropagation();
    });
    button.addEventListener("click", function (event) {
      // Prevent label default activation from opening the hidden native select on
      // mobile Safari after the custom trigger is tapped.
      event.preventDefault();
      event.stopPropagation();
      toggleCustomSelect(controller);
    });
    root.addEventListener("keydown", function (event) { handleCustomSelectKeydown(controller, event); });
    document.addEventListener("click", function (event) {
      if (!root.contains(event.target)) closeCustomSelect(controller);
    });

    select.__healthMdCustomSelect = controller;
    customSelects.push(controller);
    syncCustomSelect(controller);
    return controller;
  }

  function enhanceSelectControls() {
    ["[data-viz-data-filter]", "[data-viz-select]"].forEach(function (selector) {
      var select = app.querySelector(selector);
      if (select) enhanceSelect(select);
    });
  }

  function syncCustomSelects() {
    customSelects.forEach(syncCustomSelect);
  }

  function bindControls() {
    var colorSchemeSelect = app.querySelector("[data-viz-color-scheme]");
    colorSchemeSelect.removeAttribute("aria-hidden");
    colorSchemeSelect.removeAttribute("tabindex");

    app.querySelector("[data-viz-data-filter]").addEventListener("change", function (event) {
      state.dataFilter = event.target.value;
      render({ pushUrl: true });
    });
    app.querySelector("[data-viz-select]").addEventListener("change", function (event) {
      state.visualization = event.target.value;
      render({ pushUrl: true });
    });
    colorSchemeSelect.addEventListener("change", function (event) {
      state.colorScheme = isColorScheme(event.target.value) ? event.target.value : "theme";
      render({ pushUrl: true });
    });
    enhanceSelectControls();
    app.addEventListener("change", function (event) {
      var parameterControl = event.target.closest("[data-viz-param]");
      if (!parameterControl || !app.contains(parameterControl)) return;
      updateParameterOverride(parameterControl);
      render({ skipUrl: true });
    });
    app.addEventListener("input", function (event) {
      var parameterControl = event.target.closest("[data-viz-param]");
      if (!parameterControl || !app.contains(parameterControl) || parameterControl.tagName === "SELECT") return;
      updateParameterOverride(parameterControl);
      scheduleParameterRender();
    });
    app.addEventListener("click", function (event) {
      var themeButton = event.target.closest("[data-viz-color-option]");
      if (themeButton && app.contains(themeButton)) {
        state.colorScheme = isColorScheme(themeButton.value) ? themeButton.value : "theme";
        render({ pushUrl: true });
        return;
      }
      var resetButton = event.target.closest("[data-reset-viz-params]");
      if (resetButton && app.contains(resetButton)) {
        resetCurrentParameters();
        return;
      }
      var copyButton = event.target.closest("[data-copy-block]");
      if (!copyButton || !app.contains(copyButton)) return;
      copyBlock(copyButton);
    });

    document.querySelectorAll("[data-theme-option]").forEach(function (button) {
      button.addEventListener("click", function () {
        window.setTimeout(render, 0);
      });
    });

    var observer = new MutationObserver(function (mutations) {
      mutations.forEach(function (mutation) {
        if (mutation.attributeName === "data-theme") render();
      });
    });
    observer.observe(document.documentElement, { attributes: true });

    if (window.matchMedia) {
      var systemTheme = window.matchMedia("(prefers-color-scheme: dark)");
      var onSystemThemeChange = function () {
        if (state.themeMode === "auto") render();
      };
      if (systemTheme.addEventListener) systemTheme.addEventListener("change", onSystemThemeChange);
      else if (systemTheme.addListener) systemTheme.addListener(onSystemThemeChange);
    }

    window.addEventListener("resize", function () {
      window.clearTimeout(resizeTimer);
      resizeTimer = window.setTimeout(function () { renderPreview(currentVisualization()); }, 120);
    });

    window.addEventListener("popstate", function () {
      applyUrlState(readUrlState());
      render({ skipUrl: true });
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    app = document.querySelector("[data-viz-app]");
    if (!app) return;
    installObsidianDomShims();
    var urlState = readUrlState();
    readState();
    applyUrlState(urlState);
    bindControls();
    fetch(dataUrl).then(function (response) {
      if (!response.ok) throw new Error("Unable to load sample Health.md data");
      return response.json();
    }).then(function (data) {
      sampleData = data;
      render();
    }).catch(function (error) {
      sampleData = [];
      render();
      var errorEl = app.querySelector("[data-render-error]");
      errorEl.textContent = error.message;
      errorEl.hidden = false;
    });
  });
})();

(function () {
  var storageKey = "healthmd-viz-studio-v3";
  var dataUrl = "../assets/visualizations-data/health-sample.json";
  var app;
  var sampleData = [];
  var resizeTimer = 0;

  var state = {
    visualization: "activity-rings",
    themeMode: "auto",
    colorScheme: "theme",
    dataFilter: "Activity"
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

  function viz(id, label, category, renderer, description, tags, config) {
    return { id: id, label: label, category: category, renderer: renderer, description: description, tags: tags || [], config: config };
  }

  function option(name, values, defaultValue, effect) {
    return { name: name, values: values, defaultValue: defaultValue, effect: effect };
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

  function renderCodeBlock(viz) {
    var config = Object.assign({}, viz.config, {
      theme: state.themeMode,
      colorScheme: state.colorScheme
    });
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
    var docs = visualizationDocs[viz.id] || doc(viz.description, "Matching Health.md data for this category.", []);
    var specificOptions = docs.options && docs.options.length ? optionsTable(docs.options) : "<p class=\"docs-empty\">No renderer-specific options. Use the common date, size, theme, and color options below to adapt this block.</p>";
    panel.innerHTML = "<div class=\"docs-header\">" +
      "<span class=\"eyebrow\">Obsidian plugin docs</span>" +
      "<h3>" + escapeHtml(viz.label) + " <code>" + escapeHtml(viz.id) + "</code></h3>" +
      "<p>" + escapeHtml(docs.description || viz.description) + "</p>" +
      "</div>" +
      "<div class=\"docs-meta\">" +
      "<div><span>Renderer</span><strong>" + escapeHtml(viz.renderer === "html" ? "HTML" : "Canvas") + "</strong></div>" +
      "<div><span>Category</span><strong>" + escapeHtml(categoryLabels[viz.category] || viz.category) + "</strong></div>" +
      "<div><span>Data needed</span><strong>" + escapeHtml(docs.dataNeeded) + "</strong></div>" +
      "</div>" +
      "<div class=\"docs-section\"><h4>Renderer-specific options</h4>" + specificOptions + "</div>" +
      "<details class=\"docs-section docs-details\"><summary>Common <code>health-viz</code> block options</summary>" + optionsTable(commonVisualizationOptions) + "</details>" +
      "<div class=\"docs-section docs-code\"><h4>Copyable block for this preview</h4><pre><code>" + escapeHtml(renderCodeBlock(viz)) + "</code></pre></div>";
  }

  function renderPreview(viz) {
    var renderer = rendererForItem(viz);
    var canvas = app.querySelector("[data-viz-canvas]");
    var html = app.querySelector("[data-viz-html]");
    var stats = app.querySelector("[data-viz-stats]");
    var error = app.querySelector("[data-render-error]");
    var shell = app.querySelector(".canvas-shell");
    var config = Object.assign({}, viz.config, { theme: state.themeMode, colorScheme: state.colorScheme });
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
      error.textContent = "Renderer missing. The Health.md plugin visualization bundle did not expose “" + viz.id + "”.";
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

  function render() {
    ensureSelectionInFilter();
    var viz = currentVisualization();
    renderVisualizationSelect();
    app.querySelector("[data-current-category]").textContent = categoryLabels[viz.category] || viz.category;
    app.querySelector("[data-current-title]").textContent = viz.label;
    app.querySelector("[data-current-description]").textContent = viz.description;
    app.querySelector("[data-viz-color-scheme]").value = state.colorScheme;
    app.querySelector("[data-viz-data-filter]").value = state.dataFilter;
    app.querySelector("[data-viz-code]").textContent = renderCodeBlock(viz);
    app.querySelector("[data-code-label]").textContent = viz.id;
    renderVisualizationDocs(viz);
    renderPreview(viz);
    writeState();
  }

  function copyBlock() {
    var block = renderCodeBlock(currentVisualization());
    var button = app.querySelector("[data-copy-block]");
    if (!navigator.clipboard) return;
    navigator.clipboard.writeText(block).then(function () {
      var original = button.textContent;
      button.textContent = "Copied";
      window.setTimeout(function () { button.textContent = original; }, 1200);
    });
  }

  function bindControls() {
    app.querySelector("[data-viz-data-filter]").addEventListener("change", function (event) {
      state.dataFilter = event.target.value;
      render();
    });
    app.querySelector("[data-viz-select]").addEventListener("change", function (event) {
      state.visualization = event.target.value;
      render();
    });
    app.querySelector("[data-viz-color-scheme]").addEventListener("change", function (event) {
      state.colorScheme = isColorScheme(event.target.value) ? event.target.value : "theme";
      render();
    });
    app.querySelector("[data-copy-block]").addEventListener("click", copyBlock);

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
  }

  document.addEventListener("DOMContentLoaded", function () {
    app = document.querySelector("[data-viz-app]");
    if (!app) return;
    installObsidianDomShims();
    readState();
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

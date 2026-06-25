(function () {
  var storageKey = "healthmd-visualization-studio";
  var app = null;
  var state = { visualization: "overview", theme: "obsidian-prism" };

  var themes = [
    {
      id: "obsidian-prism",
      name: "Obsidian Prism",
      description: "A polished dark canvas with Health.md purple and teal accents.",
      bg: "#090912",
      surface: "rgba(16, 16, 27, 0.86)",
      fg: "#f8fafc",
      muted: "rgba(248, 250, 252, 0.68)",
      dim: "rgba(248, 250, 252, 0.42)",
      line: "rgba(255, 255, 255, 0.15)",
      accent: "#a37dbd",
      secondary: "#00aa95",
      heart: "#e2162a",
      warning: "#f59e0b",
      sleepDeep: "#312e81",
      sleepRem: "#8b5cf6",
      sleepCore: "#14b8a6",
      sleepAwake: "#60a5fa"
    },
    {
      id: "clinical-light",
      name: "Clinical Light",
      description: "Bright, editorial cards for health reports and clean screenshots.",
      bg: "#f6f7fb",
      surface: "rgba(255, 255, 255, 0.88)",
      fg: "#111827",
      muted: "rgba(17, 24, 39, 0.66)",
      dim: "rgba(17, 24, 39, 0.42)",
      line: "rgba(17, 24, 39, 0.13)",
      accent: "#6d5dfc",
      secondary: "#0891b2",
      heart: "#dc2626",
      warning: "#d97706",
      sleepDeep: "#172554",
      sleepRem: "#7c3aed",
      sleepCore: "#06b6d4",
      sleepAwake: "#38bdf8"
    },
    {
      id: "midnight-heart",
      name: "Midnight Heart",
      description: "High-contrast black UI with saturated cardio highlights.",
      bg: "#020204",
      surface: "rgba(11, 11, 16, 0.9)",
      fg: "#fff7ed",
      muted: "rgba(255, 247, 237, 0.66)",
      dim: "rgba(255, 247, 237, 0.4)",
      line: "rgba(255, 247, 237, 0.14)",
      accent: "#fb7185",
      secondary: "#f97316",
      heart: "#ef4444",
      warning: "#facc15",
      sleepDeep: "#4c0519",
      sleepRem: "#be123c",
      sleepCore: "#f97316",
      sleepAwake: "#fef08a"
    },
    {
      id: "aurora-lab",
      name: "Aurora Lab",
      description: "Vivid violet, cyan, and green for energetic dashboards.",
      bg: "#07111f",
      surface: "rgba(8, 19, 35, 0.86)",
      fg: "#ecfeff",
      muted: "rgba(236, 254, 255, 0.67)",
      dim: "rgba(236, 254, 255, 0.42)",
      line: "rgba(236, 254, 255, 0.15)",
      accent: "#a855f7",
      secondary: "#22c55e",
      heart: "#f43f5e",
      warning: "#eab308",
      sleepDeep: "#1e1b4b",
      sleepRem: "#7e22ce",
      sleepCore: "#06b6d4",
      sleepAwake: "#bef264"
    },
    {
      id: "forest-recovery",
      name: "Forest Recovery",
      description: "Grounded greens for recovery, sleep, and long-term wellness.",
      bg: "#07140d",
      surface: "rgba(12, 31, 18, 0.88)",
      fg: "#f0fdf4",
      muted: "rgba(240, 253, 244, 0.66)",
      dim: "rgba(240, 253, 244, 0.42)",
      line: "rgba(240, 253, 244, 0.14)",
      accent: "#22c55e",
      secondary: "#84cc16",
      heart: "#ef4444",
      warning: "#eab308",
      sleepDeep: "#052e16",
      sleepRem: "#15803d",
      sleepCore: "#4ade80",
      sleepAwake: "#bbf7d0"
    },
    {
      id: "monochrome-ink",
      name: "Monochrome Ink",
      description: "Minimal grayscale when the data needs to feel quiet.",
      bg: "#101114",
      surface: "rgba(24, 25, 29, 0.88)",
      fg: "#f5f5f5",
      muted: "rgba(245, 245, 245, 0.62)",
      dim: "rgba(245, 245, 245, 0.38)",
      line: "rgba(245, 245, 245, 0.14)",
      accent: "#d4d4d8",
      secondary: "#a1a1aa",
      heart: "#71717a",
      warning: "#e4e4e7",
      sleepDeep: "#27272a",
      sleepRem: "#52525b",
      sleepCore: "#a1a1aa",
      sleepAwake: "#fafafa"
    }
  ];

  var visualizations = [
    {
      id: "overview",
      icon: "◈",
      name: "Overview dashboard",
      shortName: "Overview",
      metric: "summary",
      description: "All-day metrics in one calm card: movement, recovery, heart rate, and sleep context.",
      height: 540,
      render: renderOverview
    },
    {
      id: "activity-rings",
      icon: "◎",
      name: "Activity rings",
      shortName: "Rings",
      metric: "steps",
      description: "Goal progress presented as concentric movement rings with supporting trends.",
      height: 520,
      render: renderRings
    },
    {
      id: "sleep-stages",
      icon: "☾",
      name: "Sleep stages",
      shortName: "Sleep",
      metric: "sleep-duration",
      description: "A sleep-stage spotlight with deep, REM, core, and awake segments separated by color.",
      height: 500,
      render: renderSleep
    },
    {
      id: "heart-zones",
      icon: "♥",
      name: "Heart zones",
      shortName: "Heart",
      metric: "heart-rate",
      description: "Cardio intensity with a line chart, zone distribution, and resting-rate context.",
      height: 510,
      render: renderHeart
    },
    {
      id: "recovery-score",
      icon: "✦",
      name: "Recovery score",
      shortName: "Recovery",
      metric: "hrv",
      description: "Recovery readiness from HRV, sleep debt, and resting heart-rate signals.",
      height: 500,
      render: renderRecovery
    },
    {
      id: "correlations",
      icon: "⌁",
      name: "Correlation map",
      shortName: "Correlate",
      metric: "correlation",
      description: "A scatter-style relationship view for comparing habits and outcomes over time.",
      height: 520,
      render: renderCorrelation
    }
  ];

  function byId(collection, id) {
    return collection.filter(function (item) { return item.id === id; })[0] || collection[0];
  }

  function readState() {
    try {
      var parsed = JSON.parse(localStorage.getItem(storageKey) || "null");
      if (parsed && typeof parsed === "object") {
        state.visualization = byId(visualizations, parsed.visualization).id;
        state.theme = byId(themes, parsed.theme).id;
      }
    } catch (_error) {
      // Ignore invalid storage.
    }
  }

  function writeState() {
    try {
      localStorage.setItem(storageKey, JSON.stringify(state));
    } catch (_error) {
      // Ignore private mode failures.
    }
  }

  function setVars(theme) {
    app.style.setProperty("--app-bg", theme.bg);
    app.style.setProperty("--app-surface", theme.surface);
    app.style.setProperty("--app-fg", theme.fg);
    app.style.setProperty("--app-muted", theme.muted);
    app.style.setProperty("--app-dim", theme.dim);
    app.style.setProperty("--app-line", theme.line);
    app.style.setProperty("--app-accent", theme.accent);
    app.style.setProperty("--app-secondary", theme.secondary);
    app.style.setProperty("--app-heart", theme.heart);
    app.style.setProperty("--app-warning", theme.warning);
    app.style.setProperty("--app-sleep-deep", theme.sleepDeep);
    app.style.setProperty("--app-sleep-rem", theme.sleepRem);
    app.style.setProperty("--app-sleep-core", theme.sleepCore);
    app.style.setProperty("--app-sleep-awake", theme.sleepAwake);
    var metaTheme = document.querySelector('meta[name="theme-color"]');
    if (metaTheme) metaTheme.setAttribute("content", theme.bg);
  }

  function renderOverview() {
    return [
      '<div class="viz-scene viz-overview">',
      renderTopline("Health summary", "Today · synced from Apple Health", "87", "score"),
      '<div class="metric-grid">',
      metric("Steps", "12,642", "+18% vs avg"),
      metric("Avg BPM", "68", "resting 54"),
      metric("Sleep", "7h 18m", "84% quality"),
      metric("HRV", "61ms", "+7ms"),
      '</div>',
      '<div class="dual-grid">',
      '<section class="graph-shell"><div class="graph-header"><strong>Activity trend</strong><span>14 days</span></div>',
      bars([42, 58, 38, 72, 64, 86, 56, 78, 92, 66, 48, 74, 88, 69]),
      '</section>',
      '<section class="graph-shell"><div class="graph-header"><strong>Sleep composition</strong><span>deep · REM · core</span></div>',
      '<div class="sleep-strip" aria-hidden="true"><span></span><span></span><span></span><span></span><span></span><span></span><span></span></div>',
      legend(),
      '</section>',
      '</div>',
      '</div>'
    ].join("");
  }

  function renderRings() {
    return [
      '<div class="viz-scene viz-rings">',
      renderTopline("Activity rings", "Move · exercise · stand", "93", "closed"),
      '<div class="ring-stage">',
      '<div class="rings" aria-label="Activity ring progress">',
      '<svg viewBox="0 0 120 120" role="img" aria-label="Move 85 percent, exercise 87 percent, stand 90 percent">',
      '<circle class="track" cx="60" cy="60" r="44"></circle><circle class="progress move" cx="60" cy="60" r="44"></circle>',
      '<circle class="track" cx="60" cy="60" r="36"></circle><circle class="progress exercise" cx="60" cy="60" r="36"></circle>',
      '<circle class="track" cx="60" cy="60" r="28"></circle><circle class="progress stand" cx="60" cy="60" r="28"></circle>',
      '</svg><div class="ring-center"><strong>820</strong><span>active kcal</span></div></div>',
      '<div class="progress-list">',
      progress("Move", "820 / 960 kcal", 85),
      progress("Exercise", "52 / 60 min", 87),
      progress("Stand", "10 / 11 hr", 90),
      progress("Steps", "12,642 / 10,000", 100),
      '</div>',
      '</div>',
      '<section class="graph-shell"><div class="graph-header"><strong>Weekly load</strong><span>volume</span></div>' + bars([52, 68, 84, 43, 92, 78, 88, 66, 73, 95, 58, 71, 82, 90]) + '</section>',
      '</div>'
    ].join("");
  }

  function renderSleep() {
    return [
      '<div class="viz-scene viz-sleep">',
      renderTopline("Sleep stages", "Last night · 10:42 PM–6:11 AM", "7:18", "asleep"),
      '<section class="graph-shell"><div class="graph-header"><strong>Hypnogram</strong><span>stage timeline</span></div>',
      '<div class="hypnogram" aria-hidden="true">',
      '<span class="core"></span><span class="deep"></span><span class="deep"></span><span class="rem"></span><span class="core"></span><span class="awake"></span><span class="core"></span><span class="rem"></span><span class="core"></span><span class="awake"></span>',
      '</div>',
      legend(),
      '</section>',
      '<div class="metric-grid">',
      metric("Deep", "1h 24m", "19%"),
      metric("REM", "1h 51m", "25%"),
      metric("Core", "3h 46m", "52%"),
      metric("Awake", "17m", "4%"),
      '</div>',
      '</div>'
    ].join("");
  }

  function renderHeart() {
    return [
      '<div class="viz-scene viz-heart">',
      renderTopline("Heart zones", "Workout · mixed cardio", "142", "peak bpm"),
      '<div class="dual-grid">',
      '<section class="graph-shell"><div class="graph-header"><strong>BPM curve</strong><span>42 min</span></div>' + lineChart() + '</section>',
      '<section class="graph-shell"><div class="graph-header"><strong>Time in zone</strong><span>intensity</span></div><div class="zone-list">',
      zone("Zone 1", "15m", 72),
      zone("Zone 2", "12m", 58),
      zone("Zone 3", "9m", 44),
      zone("Zone 4", "5m", 28),
      zone("Zone 5", "1m", 8),
      '</div></section>',
      '</div>',
      '<div class="metric-grid">',
      metric("Resting", "54", "bpm"),
      metric("Average", "118", "bpm"),
      metric("Peak", "142", "bpm"),
      metric("Recovery", "32", "bpm drop"),
      '</div>',
      '</div>'
    ].join("");
  }

  function renderRecovery() {
    return [
      '<div class="viz-scene viz-recovery">',
      renderTopline("Recovery score", "Readiness model · rolling 7 days", "82", "ready"),
      '<div class="recovery-grid">',
      recoveryTile("HRV", "61", "ms", "Above baseline by 7ms. Training capacity is trending upward."),
      recoveryTile("Sleep debt", "0.6", "hr", "Low debt. Maintain bedtime consistency tonight."),
      recoveryTile("Resting HR", "54", "bpm", "Stable and below the four-week average."),
      '</div>',
      '<section class="graph-shell"><div class="graph-header"><strong>Readiness trend</strong><span>14 days</span></div>' + bars([61, 58, 66, 70, 63, 76, 82, 79, 86, 83, 88, 84, 91, 82]) + '</section>',
      '</div>'
    ].join("");
  }

  function renderCorrelation() {
    return [
      '<div class="viz-scene viz-correlation">',
      renderTopline("Correlation map", "Caffeine timing × sleep quality", "-.62", "r value"),
      '<div class="scatter" aria-label="Scatter plot showing later caffeine associated with lower sleep quality">',
      scatterPoint(12, 84), scatterPoint(18, 78), scatterPoint(24, 74), scatterPoint(31, 68), scatterPoint(36, 73), scatterPoint(44, 58), scatterPoint(51, 55), scatterPoint(60, 48), scatterPoint(67, 43), scatterPoint(74, 36), scatterPoint(82, 32),
      '<span class="scatter-axis y">sleep quality ↑</span><span class="scatter-axis x">caffeine later →</span>',
      '</div>',
      '<div class="metric-grid">',
      metric("Samples", "42", "nights"),
      metric("Correlation", "-0.62", "moderate"),
      metric("Cutoff", "1:30p", "best"),
      metric("Impact", "+31m", "sleep"),
      '</div>',
      '</div>'
    ].join("");
  }

  function renderTopline(title, subtitle, score, label) {
    return '<div class="viz-topline"><div><h2>' + title + '</h2><p>' + subtitle + '</p></div><div class="score-pill"><strong>' + score + '</strong><span>' + label + '</span></div></div>';
  }

  function metric(label, value, detail) {
    return '<div class="metric-card"><small>' + label + '</small><strong>' + value + '</strong><span>' + detail + '</span></div>';
  }

  function bars(values) {
    return '<div class="bar-set" aria-hidden="true">' + values.map(function (value) {
      return '<span style="height:' + value + '%"></span>';
    }).join("") + '</div>';
  }

  function legend() {
    return '<div class="legend"><span><i class="legend-dot deep"></i>Deep</span><span><i class="legend-dot rem"></i>REM</span><span><i class="legend-dot core"></i>Core</span><span><i class="legend-dot awake"></i>Awake</span></div>';
  }

  function progress(label, value, percent) {
    return '<div class="progress-row"><header><span>' + label + '</span><strong>' + value + '</strong></header><div class="progress-track"><span style="width:' + Math.min(percent, 100) + '%"></span></div></div>';
  }

  function lineChart() {
    return [
      '<div class="line-chart" aria-hidden="true"><svg viewBox="0 0 520 250" preserveAspectRatio="none">',
      '<defs><linearGradient id="areaGradient" x1="0" x2="0" y1="0" y2="1"><stop offset="0%" stop-color="var(--app-heart)" stop-opacity="0.42"/><stop offset="100%" stop-color="var(--app-heart)" stop-opacity="0"/></linearGradient></defs>',
      '<path class="grid" d="M0 50H520M0 100H520M0 150H520M0 200H520"></path>',
      '<path class="area" d="M0 176 C44 160 64 122 104 130 C156 140 157 74 208 82 C260 92 269 50 312 58 C366 65 371 115 416 102 C460 90 474 58 520 68 L520 250 L0 250 Z"></path>',
      '<path class="line" d="M0 176 C44 160 64 122 104 130 C156 140 157 74 208 82 C260 92 269 50 312 58 C366 65 371 115 416 102 C460 90 474 58 520 68"></path>',
      '</svg></div>'
    ].join("");
  }

  function zone(label, value, width) {
    return '<div class="zone"><span>' + label + '</span><div><span style="width:' + width + '%"></span></div><strong>' + value + '</strong></div>';
  }

  function recoveryTile(label, value, unit, copy) {
    return '<article class="recovery-tile"><small>' + label + '</small><strong>' + value + '<span>' + unit + '</span></strong><p>' + copy + '</p></article>';
  }

  function scatterPoint(x, y) {
    return '<span class="scatter-point" style="left:' + x + '%;bottom:' + y + '%"></span>';
  }

  function buildBlock(viz, theme) {
    return [
      "```health-viz",
      "type: " + viz.id,
      "metric: " + viz.metric,
      "last: 14",
      "width: 920",
      "height: " + viz.height,
      "theme: auto",
      "colorScheme: custom",
      "background: " + theme.bg,
      "foreground: " + theme.fg,
      "muted: " + rgbaToHexish(theme.muted),
      "accent: " + theme.accent,
      "secondary: " + theme.secondary,
      "heart: " + theme.heart,
      "sleepDeep: " + theme.sleepDeep,
      "sleepRem: " + theme.sleepRem,
      "sleepCore: " + theme.sleepCore,
      "sleepAwake: " + theme.sleepAwake,
      "```"
    ].join("\n");
  }

  function rgbaToHexish(value) {
    return value.indexOf("rgba") === 0 ? value : value;
  }

  function renderSelectors(viz, theme) {
    var dock = app.querySelector("[data-quick-dock]");
    var library = app.querySelector("[data-library-list]");
    var themeList = app.querySelector("[data-theme-list]");

    dock.innerHTML = visualizations.map(function (item) {
      var active = item.id === viz.id;
      return '<button type="button" data-select-viz="' + item.id + '" aria-pressed="' + active + '" title="' + item.name + '"><span aria-hidden="true">' + item.icon + '</span><em>' + item.shortName + '</em></button>';
    }).join("");

    library.innerHTML = visualizations.map(function (item, index) {
      var active = item.id === viz.id;
      return '<button class="viz-card" type="button" data-select-viz="' + item.id + '" aria-pressed="' + active + '"><span class="viz-card-icon" aria-hidden="true">' + item.icon + '</span><span><strong>' + item.name + '</strong><small>' + item.description + '</small></span><kbd>' + (index + 1) + '</kbd></button>';
    }).join("");

    themeList.innerHTML = themes.map(function (item) {
      var active = item.id === theme.id;
      return '<button class="theme-card" type="button" data-select-app-theme="' + item.id + '" aria-pressed="' + active + '"><span><strong>' + item.name + '</strong><small>' + item.description + '</small></span><span class="swatches" aria-hidden="true"><span style="background:' + item.accent + '"></span><span style="background:' + item.secondary + '"></span><span style="background:' + item.heart + '"></span></span></button>';
    }).join("");
  }

  function render() {
    var viz = byId(visualizations, state.visualization);
    var theme = byId(themes, state.theme);
    setVars(theme);

    app.querySelector("[data-current-viz-name]").textContent = viz.name;
    app.querySelector("[data-current-theme-name]").textContent = theme.name;
    app.querySelector("[data-spotlight-title]").textContent = viz.name;
    app.querySelector("[data-spotlight-description]").textContent = viz.description;
    app.querySelector("[data-stage-label]").textContent = theme.name + " preview";
    app.querySelector("[data-stage-subtitle]").textContent = "Obsidian note width · 920px";
    app.querySelector("[data-viz-canvas]").innerHTML = viz.render();
    app.querySelector("[data-viz-code]").textContent = buildBlock(viz, theme);
    app.querySelector("[data-export-label]").textContent = "theme: " + theme.id;

    renderSelectors(viz, theme);
    bindDynamicButtons();
    writeState();
  }

  function bindDynamicButtons() {
    app.querySelectorAll("[data-select-viz]").forEach(function (button) {
      button.addEventListener("click", function () {
        state.visualization = byId(visualizations, button.getAttribute("data-select-viz")).id;
        closePanels();
        render();
      });
    });
    app.querySelectorAll("[data-select-app-theme]").forEach(function (button) {
      button.addEventListener("click", function () {
        state.theme = byId(themes, button.getAttribute("data-select-app-theme")).id;
        render();
      });
    });
  }

  function openPanel(name) {
    app.querySelectorAll("[data-panel]").forEach(function (panel) {
      var open = panel.getAttribute("data-panel") === name;
      panel.classList.toggle("is-open", open);
      panel.setAttribute("aria-hidden", open ? "false" : "true");
    });
    app.querySelectorAll("[data-open-panel]").forEach(function (button) {
      button.setAttribute("aria-expanded", button.getAttribute("data-open-panel") === name ? "true" : "false");
    });
    var scrim = app.querySelector("[data-scrim]");
    if (scrim) scrim.hidden = false;
  }

  function closePanels() {
    app.querySelectorAll("[data-panel]").forEach(function (panel) {
      panel.classList.remove("is-open");
      panel.setAttribute("aria-hidden", "true");
    });
    app.querySelectorAll("[data-open-panel]").forEach(function (button) {
      button.setAttribute("aria-expanded", "false");
    });
    var scrim = app.querySelector("[data-scrim]");
    if (scrim) scrim.hidden = true;
  }

  function copyBlock() {
    var viz = byId(visualizations, state.visualization);
    var theme = byId(themes, state.theme);
    var block = buildBlock(viz, theme);
    var button = app.querySelector("[data-copy-block]");
    if (!navigator.clipboard) return;
    navigator.clipboard.writeText(block).then(function () {
      var original = button.textContent;
      button.textContent = "Copied";
      window.setTimeout(function () { button.textContent = original; }, 1200);
    }).catch(function () {
      // The exported block remains visible in the theme panel as a fallback.
    });
  }

  function bindStaticControls() {
    app.querySelectorAll("[data-open-panel]").forEach(function (button) {
      button.addEventListener("click", function () {
        var name = button.getAttribute("data-open-panel");
        var expanded = button.getAttribute("aria-expanded") === "true";
        if (expanded) closePanels();
        else openPanel(name);
      });
    });
    app.querySelectorAll("[data-close-panel]").forEach(function (button) {
      button.addEventListener("click", closePanels);
    });
    var scrim = app.querySelector("[data-scrim]");
    if (scrim) scrim.addEventListener("click", closePanels);
    var copy = app.querySelector("[data-copy-block]");
    if (copy) copy.addEventListener("click", copyBlock);

    document.addEventListener("keydown", function (event) {
      if (event.target && /input|select|textarea/i.test(event.target.tagName)) return;
      if (event.key === "Escape") closePanels();
      if (event.key.toLowerCase() === "v") openPanel("library");
      if (event.key.toLowerCase() === "t") openPanel("themes");
      var index = Number(event.key) - 1;
      if (index >= 0 && index < visualizations.length) {
        state.visualization = visualizations[index].id;
        closePanels();
        render();
      }
    });
  }

  document.addEventListener("DOMContentLoaded", function () {
    app = document.querySelector("[data-viz-app]");
    if (!app) return;
    readState();
    bindStaticControls();
    render();
  });
})();

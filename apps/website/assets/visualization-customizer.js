(function () {
  var storageKey = "healthmd-viz-studio-v2";
  var dataUrl = "../assets/visualizations-data/health-sample.json";
  var app;
  var sampleData = [];
  var resizeTimer = 0;

  var state = {
    visualization: "activity-rings",
    themeMode: "auto",
    colorScheme: "theme"
  };

  var visualizations = [
    {
      id: "activity-rings",
      label: "Activity Rings",
      category: "Activity",
      description: "Move, Exercise, and Stand rings rendered by the Obsidian plugin.",
      config: { type: "activity-rings", to: "2026-05-17", last: 1, height: 260, moveGoal: 650, exerciseGoal: 45, standGoal: 12 }
    },
    {
      id: "bar-chart",
      label: "Bar Chart",
      category: "Activity",
      description: "Daily metric bars with plugin goal and average reference lines.",
      config: { type: "bar-chart", metric: "steps", to: "2026-05-17", last: 14, height: 360, goal: 10000, showAverage: "true" }
    },
    {
      id: "sleep-quality-bars",
      label: "Sleep Quality Bars",
      category: "Sleep",
      description: "Nightly sleep-stage composition using deep, REM, core, and awake colors.",
      config: { type: "sleep-quality-bars", to: "2026-05-17", last: 14, height: 360 }
    },
    {
      id: "sleep-schedule",
      label: "Sleep Schedule",
      category: "Sleep",
      description: "Bedtime and wake consistency across the selected Health.md export window.",
      config: { type: "sleep-schedule", to: "2026-05-17", last: 14, height: 420, sleepGoal: 8 }
    },
    {
      id: "heart-range",
      label: "Heart Range",
      category: "Heart",
      description: "Daily min, max, and average heart-rate ranges from the plugin renderer.",
      config: { type: "heart-range", metric: "heart-rate", to: "2026-05-17", last: 14, height: 360 }
    },
    {
      id: "hrv-trend",
      label: "HRV Trend",
      category: "Heart",
      description: "A heart-rate variability trend chart drawn from bundled Health.md samples.",
      config: { type: "hrv-trend", to: "2026-05-17", last: 30, height: 360 }
    },
    {
      id: "oxygen-range",
      label: "Oxygen Range",
      category: "Vitals",
      description: "Daily SpO₂ range visualization using the plugin range chart core.",
      config: { type: "oxygen-range", metric: "blood-oxygen", to: "2026-05-17", last: 14, height: 360 }
    },
    {
      id: "weekday-average",
      label: "Weekday Average",
      category: "Trends",
      description: "Average metric values grouped by weekday with plugin aggregation logic.",
      config: { type: "weekday-average", metric: "steps", weekStart: "monday", to: "2026-05-17", last: 30, height: 360 }
    }
  ];

  function installObsidianDomShims() {
    window.activeWindow = window;
    window.activeDocument = document;

    if (!HTMLElement.prototype.empty) {
      HTMLElement.prototype.empty = function () { this.textContent = ""; };
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
    if (options.cls) el.className = options.cls;
    if (options.text !== undefined) el.textContent = String(options.text);
    if (options.attr) {
      Object.keys(options.attr).forEach(function (key) {
        el.setAttribute(key, options.attr[key]);
      });
    }
  }

  function readState() {
    try {
      var parsed = JSON.parse(localStorage.getItem(storageKey) || "null");
      if (!parsed || typeof parsed !== "object") return;
      if (byId(visualizations, parsed.visualization)) state.visualization = parsed.visualization;
      if (["auto", "light", "dark"].indexOf(parsed.themeMode) >= 0) state.themeMode = parsed.themeMode;
      if (isColorScheme(parsed.colorScheme)) state.colorScheme = parsed.colorScheme;
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
    return byId(visualizations, state.visualization) || visualizations[0];
  }

  function pluginApi() {
    return window.HealthMdPluginVisualizations || { renderers: {}, colorSchemes: {} };
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
    document.body.style.setProperty("--text-normal", cssVar("--color-primary", isDark ? "#ededed" : "#171717"));
    document.body.style.setProperty("--text-muted", cssVar("--color-secondary", isDark ? "#a0a0a0" : "#4d4d4d"));
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

  function renderVisualizationList() {
    var list = app.querySelector("[data-visualization-list]");
    list.innerHTML = visualizations.map(function (item) {
      return [
        '<button class="option-card" type="button" data-select-viz="', item.id, '" aria-pressed="', item.id === state.visualization ? "true" : "false", '">',
        '<strong>', item.label, '</strong>',
        '<small>', item.category, ' · type: ', item.id, '</small>',
        '</button>'
      ].join("");
    }).join("");

    list.querySelectorAll("[data-select-viz]").forEach(function (button) {
      button.addEventListener("click", function () {
        state.visualization = button.getAttribute("data-select-viz");
        render();
      });
    });
  }

  function renderCodeBlock(viz) {
    var config = Object.assign({}, viz.config, {
      theme: state.themeMode,
      colorScheme: state.colorScheme
    });
    var order = ["type", "metric", "to", "last", "height", "theme", "colorScheme", "goal", "showAverage", "moveGoal", "exerciseGoal", "standGoal", "sleepGoal", "weekStart"];
    var lines = ["```health-viz"];
    order.forEach(function (key) {
      if (config[key] !== undefined) lines.push(key + ": " + config[key]);
    });
    lines.push("```");
    return lines.join("\n");
  }

  function renderCanvas(viz) {
    var api = pluginApi();
    var renderer = api.renderers[viz.id];
    var canvas = app.querySelector("[data-viz-canvas]");
    var stats = app.querySelector("[data-viz-stats]");
    var error = app.querySelector("[data-render-error]");
    var shell = app.querySelector(".canvas-shell");
    var config = Object.assign({}, viz.config, { theme: state.themeMode, colorScheme: state.colorScheme });
    var activeTheme = resolvedTheme(config);
    var width = Math.max(320, Math.min(760, shell.clientWidth - 48 || 760));
    var height = Number(config.height) || 360;

    error.hidden = true;
    canvas.hidden = false;
    stats.empty();

    if (!renderer) {
      error.textContent = "Renderer missing. The Health.md plugin visualization bundle did not expose “" + viz.id + "”.";
      error.hidden = false;
      canvas.hidden = true;
      return;
    }

    try {
      var ctx = setupCanvas(canvas, width, height);
      renderer(ctx, filteredData(config), width, height, config, activeTheme, stats, { add: function () {} });
    } catch (err) {
      error.textContent = "Render failed. " + (err && err.message ? err.message : String(err));
      error.hidden = false;
      canvas.hidden = true;
      console.error(err);
    }
  }

  function render() {
    var viz = currentVisualization();
    renderVisualizationList();
    app.querySelector("[data-current-category]").textContent = viz.category;
    app.querySelector("[data-current-title]").textContent = viz.label;
    app.querySelector("[data-current-description]").textContent = viz.description;
    app.querySelector("[data-viz-theme-mode]").value = state.themeMode;
    app.querySelector("[data-viz-color-scheme]").value = state.colorScheme;
    app.querySelector("[data-viz-code]").textContent = renderCodeBlock(viz);
    app.querySelector("[data-code-label]").textContent = viz.id;
    renderCanvas(viz);
    writeState();
  }

  function copyBlock() {
    var block = renderCodeBlock(currentVisualization());
    var button = app.querySelector("[data-copy-block]");
    if (!navigator.clipboard) return;
    navigator.clipboard.writeText(block).then(function () {
      var original = button.textContent;
      button.textContent = "Block Copied";
      window.setTimeout(function () { button.textContent = original; }, 1200);
    });
  }

  function bindControls() {
    app.querySelector("[data-viz-theme-mode]").addEventListener("change", function (event) {
      state.themeMode = event.target.value;
      render();
    });
    app.querySelector("[data-viz-color-scheme]").addEventListener("change", function (event) {
      state.colorScheme = isColorScheme(event.target.value) ? event.target.value : "theme";
      render();
    });
    app.querySelector("[data-copy-block]").addEventListener("click", copyBlock);

    document.querySelectorAll("[data-theme-option]").forEach(function (button) {
      button.addEventListener("click", function () {
        var option = button.getAttribute("data-theme-option");
        window.setTimeout(function () {
          state.themeMode = option === "light" || option === "dark" ? option : "auto";
          render();
        }, 0);
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
      resizeTimer = window.setTimeout(function () { renderCanvas(currentVisualization()); }, 120);
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

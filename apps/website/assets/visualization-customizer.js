(function () {
  var storageKey = "healthmd-viz-customizer";
  var colorKeys = [
    "accent",
    "secondary",
    "heart",
    "background",
    "foreground",
    "muted",
    "sleepDeep",
    "sleepRem",
    "sleepCore",
    "sleepAwake"
  ];

  var chartTypes = {
    "summary-card": {
      label: "Summary card",
      metric: "hrv",
      height: 360,
      title: "summary-card preview",
      chartTitle: "HRV trend",
      chartMeta: "last 14 days"
    },
    "bar-chart": {
      label: "Bar chart",
      metric: "steps",
      height: 400,
      title: "bar-chart preview",
      chartTitle: "Daily steps",
      chartMeta: "last 14 days"
    },
    "sleep-quality-bars": {
      label: "Sleep stages",
      metric: "sleep-duration",
      height: 420,
      title: "sleep-quality-bars preview",
      chartTitle: "Sleep duration",
      chartMeta: "stage colors"
    },
    "activity-rings": {
      label: "Activity rings",
      metric: "steps",
      height: 420,
      title: "activity-rings preview",
      chartTitle: "Move · Exercise · Stand",
      chartMeta: "goal progress"
    }
  };

  var devices = {
    phone: { label: "Phone", width: 360, configWidth: 360 },
    note: { label: "Obsidian note", width: 680, configWidth: 680 },
    dashboard: { label: "Dashboard", width: 920, configWidth: 920 },
    desktop: { label: "Desktop", width: 1120, configWidth: 1120 }
  };

  var palettes = {
    default: {
      accent: "#2dd4bf",
      secondary: "#f59e0b",
      heart: "#ef4444",
      sleepDeep: "#312e81",
      sleepRem: "#7c3aed",
      sleepCore: "#2dd4bf",
      sleepAwake: "#f59e0b"
    },
    ocean: {
      accent: "#0ea5e9",
      secondary: "#38bdf8",
      heart: "#e11d48",
      sleepDeep: "#0c2461",
      sleepRem: "#1d4ed8",
      sleepCore: "#0ea5e9",
      sleepAwake: "#7dd3fc"
    },
    forest: {
      accent: "#22c55e",
      secondary: "#84cc16",
      heart: "#ef4444",
      sleepDeep: "#14532d",
      sleepRem: "#15803d",
      sleepCore: "#4ade80",
      sleepAwake: "#bbf7d0"
    },
    sunset: {
      accent: "#f97316",
      secondary: "#ec4899",
      heart: "#ef4444",
      sleepDeep: "#7f1d1d",
      sleepRem: "#be185d",
      sleepCore: "#f97316",
      sleepAwake: "#fbbf24"
    },
    aurora: {
      accent: "#a855f7",
      secondary: "#06b6d4",
      heart: "#f43f5e",
      sleepDeep: "#1e1b4b",
      sleepRem: "#6d28d9",
      sleepCore: "#a855f7",
      sleepAwake: "#818cf8"
    },
    monochrome: {
      accent: "#94a3b8",
      secondary: "#64748b",
      heart: "#475569",
      sleepDeep: "#0f172a",
      sleepRem: "#334155",
      sleepCore: "#64748b",
      sleepAwake: "#cbd5e1"
    }
  };

  function cssVar(name, fallback) {
    var value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
    return toHex(value || fallback) || fallback;
  }

  function componentToHex(value) {
    var hex = Math.max(0, Math.min(255, Math.round(Number(value)))).toString(16);
    return hex.length === 1 ? "0" + hex : hex;
  }

  function rgbToHex(r, g, b) {
    return "#" + componentToHex(r) + componentToHex(g) + componentToHex(b);
  }

  function toHex(value) {
    if (!value) return null;
    var trimmed = String(value).trim();
    var short = /^#([0-9a-f]{3})$/i.exec(trimmed);
    if (short) {
      return "#" + short[1].split("").map(function (part) { return part + part; }).join("").toLowerCase();
    }
    if (/^#[0-9a-f]{6}$/i.test(trimmed)) return trimmed.toLowerCase();
    var rgb = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)/i.exec(trimmed);
    if (rgb) return rgbToHex(rgb[1], rgb[2], rgb[3]);

    var probe = document.createElement("span");
    probe.style.color = trimmed;
    if (!probe.style.color) return null;
    document.body.appendChild(probe);
    var computed = getComputedStyle(probe).color;
    probe.remove();
    rgb = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)/i.exec(computed);
    return rgb ? rgbToHex(rgb[1], rgb[2], rgb[3]) : null;
  }

  function themePalette() {
    return {
      palette: "theme",
      accent: cssVar("--color-tertiary", "#8a66aa"),
      secondary: cssVar("--color-teal-700", "#00ac96"),
      heart: cssVar("--color-red-800", "#ea001d"),
      background: cssVar("--color-background-100", "#ffffff"),
      foreground: cssVar("--color-primary", "#171717"),
      muted: cssVar("--color-secondary", "#4d4d4d"),
      sleepDeep: cssVar("--color-purple-1000", "#2d1f4f"),
      sleepRem: cssVar("--color-purple-700", "#8a66aa"),
      sleepCore: cssVar("--color-teal-700", "#00ac96"),
      sleepAwake: cssVar("--color-blue-700", "#006bff")
    };
  }

  function defaultState() {
    return Object.assign({ type: "summary-card", device: "note" }, themePalette());
  }

  function readState() {
    try {
      var parsed = JSON.parse(localStorage.getItem(storageKey) || "null");
      if (parsed && typeof parsed === "object") return Object.assign(defaultState(), parsed);
    } catch (_error) {
      // Ignore invalid persisted state.
    }
    return defaultState();
  }

  function writeState(state) {
    try {
      localStorage.setItem(storageKey, JSON.stringify(state));
    } catch (_error) {
      // Ignore private-mode storage failures.
    }
  }

  function pluginPaletteName(state) {
    if (state.palette === "theme") return "theme";
    return palettes[state.palette] ? state.palette : "custom";
  }

  function buildCode(state) {
    var chart = chartTypes[state.type] || chartTypes["summary-card"];
    var device = devices[state.device] || devices.note;
    return [
      "```health-viz",
      "type: " + state.type,
      "metric: " + chart.metric,
      "last: 14",
      "width: " + device.configWidth,
      "height: " + chart.height,
      "theme: auto",
      "colorScheme: " + pluginPaletteName(state),
      "background: " + state.background,
      "foreground: " + state.foreground,
      "muted: " + state.muted,
      "accent: " + state.accent,
      "secondary: " + state.secondary,
      "heart: " + state.heart,
      "sleepDeep: " + state.sleepDeep,
      "sleepRem: " + state.sleepRem,
      "sleepCore: " + state.sleepCore,
      "sleepAwake: " + state.sleepAwake,
      "```"
    ].join("\n");
  }

  function applyPaletteColors(state, paletteName) {
    state.palette = paletteName;
    if (paletteName === "theme") {
      Object.assign(state, themePalette());
      return;
    }
    if (palettes[paletteName]) {
      Object.assign(state, palettes[paletteName]);
      var theme = themePalette();
      state.background = theme.background;
      state.foreground = theme.foreground;
      state.muted = theme.muted;
    }
  }

  function initCustomizer(root) {
    var state = readState();
    var preview = root.querySelector("[data-viz-preview]");
    var paletteSelect = root.querySelector("[data-viz-palette]");
    var typeSelect = root.querySelector("[data-viz-type]");
    var previewLabel = root.querySelector("[data-viz-preview-label]");
    var title = root.querySelector("[data-viz-title]");
    var chartTitle = root.querySelector("[data-viz-chart-title]");
    var chartMeta = root.querySelector("[data-viz-chart-meta]");
    var code = root.querySelector("[data-viz-code]");
    var copyButton = root.querySelector("[data-viz-copy]");
    var resetButton = root.querySelector("[data-viz-reset]");
    var frame = root.querySelector("[data-viz-device-frame]");
    var deviceLabel = root.querySelector("[data-viz-device-label]");
    var deviceButtons = root.querySelectorAll("[data-viz-device]");
    var colorInputs = root.querySelectorAll("[data-viz-color]");

    function render() {
      var chart = chartTypes[state.type] || chartTypes["summary-card"];
      var device = devices[state.device] || devices.note;

      preview.style.setProperty("--viz-bg", state.background);
      preview.style.setProperty("--viz-fg", state.foreground);
      preview.style.setProperty("--viz-muted", state.muted);
      preview.style.setProperty("--viz-accent", state.accent);
      preview.style.setProperty("--viz-secondary", state.secondary);
      preview.style.setProperty("--viz-heart", state.heart);
      preview.style.setProperty("--viz-sleep-deep", state.sleepDeep);
      preview.style.setProperty("--viz-sleep-rem", state.sleepRem);
      preview.style.setProperty("--viz-sleep-core", state.sleepCore);
      preview.style.setProperty("--viz-sleep-awake", state.sleepAwake);

      if (frame) frame.style.setProperty("--device-width", device.width + "px");
      if (typeSelect) typeSelect.value = chartTypes[state.type] ? state.type : "summary-card";
      paletteSelect.value = palettes[state.palette] || state.palette === "theme" || state.palette === "custom" ? state.palette : "theme";
      colorInputs.forEach(function (input) {
        var key = input.getAttribute("data-viz-color");
        input.value = toHex(state[key]) || "#000000";
      });
      deviceButtons.forEach(function (button) {
        var active = button.getAttribute("data-viz-device") === state.device;
        button.setAttribute("aria-pressed", active ? "true" : "false");
      });

      if (title) title.textContent = chart.title;
      if (chartTitle) chartTitle.textContent = chart.chartTitle;
      if (chartMeta) chartMeta.textContent = chart.chartMeta;
      if (deviceLabel) deviceLabel.textContent = device.label + " width";
      previewLabel.textContent = "colorScheme: " + pluginPaletteName(state) + " · " + device.label;
      code.textContent = buildCode(state);
      writeState(state);
    }

    if (typeSelect) {
      typeSelect.addEventListener("change", function () {
        state.type = chartTypes[typeSelect.value] ? typeSelect.value : "summary-card";
        render();
      });
    }

    paletteSelect.addEventListener("change", function () {
      applyPaletteColors(state, paletteSelect.value);
      render();
    });

    deviceButtons.forEach(function (button) {
      button.addEventListener("click", function () {
        var nextDevice = button.getAttribute("data-viz-device");
        state.device = devices[nextDevice] ? nextDevice : "note";
        render();
      });
    });

    colorInputs.forEach(function (input) {
      input.addEventListener("input", function () {
        var key = input.getAttribute("data-viz-color");
        if (colorKeys.indexOf(key) < 0) return;
        state[key] = input.value;
        state.palette = "custom";
        render();
      });
    });

    resetButton.addEventListener("click", function () {
      var previousType = state.type;
      var previousDevice = state.device;
      state = defaultState();
      state.type = previousType;
      state.device = previousDevice;
      render();
    });

    copyButton.addEventListener("click", function () {
      var text = buildCode(state);
      if (!navigator.clipboard) return;
      navigator.clipboard.writeText(text).then(function () {
        var original = copyButton.textContent;
        copyButton.textContent = "Copied";
        window.setTimeout(function () { copyButton.textContent = original; }, 1200);
      }).catch(function () {
        // Leave the visible code block as the fallback.
      });
    });

    var observer = new MutationObserver(function (mutations) {
      mutations.forEach(function (mutation) {
        if (mutation.attributeName === "data-theme" && state.palette === "theme") {
          Object.assign(state, themePalette());
          render();
        }
      });
    });
    observer.observe(document.documentElement, { attributes: true });

    render();
  }

  document.addEventListener("DOMContentLoaded", function () {
    document.querySelectorAll("[data-viz-customizer]").forEach(initCustomizer);
  });
})();

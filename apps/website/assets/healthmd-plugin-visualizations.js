// Generated from obsidian-health-md src/visualizations. Do not edit directly.
// Run: npm run visualizations:bundle
(() => {
  // ../../obsidian-plugin-hub/obsidian-health-md/src/canvas-utils.ts
  var COLOR_SCHEMES = {
    default: {
      label: "Default",
      accent: "#2dd4bf",
      secondary: "#f59e0b",
      heart: "#ef4444",
      sleepDeep: "#312e81",
      sleepRem: "#7c3aed",
      sleepCore: "#2dd4bf",
      sleepAwake: "#f59e0b"
    },
    ocean: {
      label: "Ocean",
      accent: "#0ea5e9",
      secondary: "#38bdf8",
      heart: "#e11d48",
      sleepDeep: "#0c2461",
      sleepRem: "#1d4ed8",
      sleepCore: "#0ea5e9",
      sleepAwake: "#7dd3fc"
    },
    forest: {
      label: "Forest",
      accent: "#22c55e",
      secondary: "#84cc16",
      heart: "#ef4444",
      sleepDeep: "#14532d",
      sleepRem: "#15803d",
      sleepCore: "#4ade80",
      sleepAwake: "#bbf7d0"
    },
    sunset: {
      label: "Sunset",
      accent: "#f97316",
      secondary: "#ec4899",
      heart: "#ef4444",
      sleepDeep: "#7f1d1d",
      sleepRem: "#be185d",
      sleepCore: "#f97316",
      sleepAwake: "#fbbf24"
    },
    aurora: {
      label: "Aurora",
      accent: "#a855f7",
      secondary: "#06b6d4",
      heart: "#f43f5e",
      sleepDeep: "#1e1b4b",
      sleepRem: "#6d28d9",
      sleepCore: "#a855f7",
      sleepAwake: "#818cf8"
    },
    monochrome: {
      label: "Monochrome",
      accent: "#94a3b8",
      secondary: "#64748b",
      heart: "#475569",
      sleepDeep: "#0f172a",
      sleepRem: "#334155",
      sleepCore: "#64748b",
      sleepAwake: "#cbd5e1"
    }
  };
  function formatDate(iso) {
    const d = /* @__PURE__ */ new Date(iso + "T00:00:00");
    return d.toLocaleDateString("en-US", {
      weekday: "short",
      month: "short",
      day: "numeric",
      year: "numeric"
    });
  }
  function formatDuration(seconds) {
    const h = Math.floor(seconds / 3600);
    const m = Math.round(seconds % 3600 / 60);
    if (h === 0) return `${m}m`;
    return `${h}h ${m}m`;
  }
  function hexToRgba(hex, alpha) {
    const normalized = normalizeColor(hex, "#000000");
    const r = parseInt(normalized.slice(1, 3), 16);
    const g = parseInt(normalized.slice(3, 5), 16);
    const b = parseInt(normalized.slice(5, 7), 16);
    return `rgba(${r},${g},${b},${alpha})`;
  }
  function normalizeHexColor(value) {
    const trimmed = value.trim();
    const short = /^#([0-9a-f]{3})$/i.exec(trimmed);
    if (short) {
      return `#${short[1].split("").map((c) => c + c).join("")}`.toLowerCase();
    }
    if (/^#[0-9a-f]{6}$/i.test(trimmed)) return trimmed.toLowerCase();
    return null;
  }
  function rgbToHex(r, g, b) {
    return `#${[r, g, b].map((n) => Math.max(0, Math.min(255, Math.round(n))).toString(16).padStart(2, "0")).join("")}`;
  }
  function parseRgbColor(value) {
    const match = /^rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*[\d.]+)?\s*\)$/i.exec(value.trim());
    if (!match) return null;
    return rgbToHex(Number(match[1]), Number(match[2]), Number(match[3]));
  }
  function cssColorToHex(value) {
    var _a;
    const trimmed = value.trim();
    if (!trimmed) return null;
    const hex = normalizeHexColor(trimmed);
    if (hex) return hex;
    const rgb = parseRgbColor(trimmed);
    if (rgb) return rgb;
    try {
      const probe = activeDocument.createElement("span");
      probe.style.color = trimmed;
      if (!probe.style.color && !trimmed.startsWith("var(")) return null;
      activeDocument.body.appendChild(probe);
      const computed = activeWindow.getComputedStyle(probe).color;
      probe.remove();
      return (_a = parseRgbColor(computed)) != null ? _a : normalizeHexColor(computed);
    } catch (e) {
      return null;
    }
  }
  function normalizeColor(value, fallback) {
    var _a;
    if (typeof value !== "string") return fallback;
    return (_a = cssColorToHex(value)) != null ? _a : fallback;
  }
  function getCssColor(name, fallback) {
    try {
      const value = activeWindow.getComputedStyle(activeDocument.body).getPropertyValue(name);
      return normalizeColor(value, fallback);
    } catch (e) {
      return fallback;
    }
  }
  function configColor(config, keys, fallback) {
    if (!config) return fallback;
    for (const key of keys) {
      const value = config[key];
      if (typeof value === "string") {
        const color = normalizeColor(value, "");
        if (color) return color;
      }
    }
    return fallback;
  }
  function normalizeThemeMode(value, fallback) {
    if (typeof value !== "string") return fallback;
    const mode = value.trim().toLowerCase();
    return mode === "auto" || mode === "dark" || mode === "light" ? mode : fallback;
  }
  function normalizeColorScheme(value) {
    if (typeof value !== "string") return null;
    const scheme = value.trim().toLowerCase();
    if (scheme === "theme" || scheme === "custom") return scheme;
    if (Object.prototype.hasOwnProperty.call(COLOR_SCHEMES, scheme)) {
      return scheme;
    }
    return null;
  }
  function resolveTheme(settings, config) {
    var _a;
    const themeMode = normalizeThemeMode(config == null ? void 0 : config.theme, settings.theme);
    let isDark;
    if (themeMode === "auto") {
      isDark = activeDocument.body.classList.contains("theme-dark");
    } else {
      isDark = themeMode === "dark";
    }
    const fallbackBase = isDark ? { bg: "#0a0a0f", fg: "#e0e0e0", muted: "#555555", isDark: true } : { bg: "#ffffff", fg: "#1a1a1a", muted: "#999999", isDark: false };
    const obsidianBase = themeMode === "auto" ? {
      bg: getCssColor("--background-primary", fallbackBase.bg),
      fg: getCssColor("--text-normal", fallbackBase.fg),
      muted: getCssColor("--text-muted", fallbackBase.muted),
      isDark
    } : fallbackBase;
    const requestedScheme = normalizeColorScheme((_a = config == null ? void 0 : config.colorScheme) != null ? _a : config == null ? void 0 : config.palette);
    const scheme = requestedScheme != null ? requestedScheme : settings.colorScheme;
    const preset = scheme !== "custom" && scheme !== "theme" ? COLOR_SCHEMES[scheme] : void 0;
    const themeAccent = getCssColor("--interactive-accent", getCssColor("--color-accent", settings.colorAccent));
    const themeSecondary = getCssColor("--text-accent", getCssColor("--interactive-accent-hover", settings.colorSecondary));
    const palette = preset ? {
      accent: preset.accent,
      secondary: preset.secondary,
      heart: preset.heart,
      sleepDeep: preset.sleepDeep,
      sleepRem: preset.sleepRem,
      sleepCore: preset.sleepCore,
      sleepAwake: preset.sleepAwake
    } : scheme === "theme" ? {
      accent: themeAccent,
      secondary: themeSecondary,
      heart: settings.colorHeart,
      sleepDeep: settings.colorSleepDeep,
      sleepRem: settings.colorSleepRem,
      sleepCore: themeAccent,
      sleepAwake: settings.colorSleepAwake
    } : {
      accent: settings.colorAccent,
      secondary: settings.colorSecondary,
      heart: settings.colorHeart,
      sleepDeep: settings.colorSleepDeep,
      sleepRem: settings.colorSleepRem,
      sleepCore: settings.colorSleepCore,
      sleepAwake: settings.colorSleepAwake
    };
    return {
      bg: configColor(config, ["background", "bg", "colorBackground"], obsidianBase.bg),
      fg: configColor(config, ["foreground", "fg", "text", "colorForeground"], obsidianBase.fg),
      muted: configColor(config, ["muted", "textMuted", "colorMuted"], obsidianBase.muted),
      isDark,
      colors: {
        accent: configColor(config, ["accent", "colorAccent"], palette.accent),
        secondary: configColor(config, ["secondary", "colorSecondary"], palette.secondary),
        heart: configColor(config, ["heart", "heartRate", "colorHeart"], palette.heart),
        sleep: {
          deep: configColor(config, ["sleepDeep", "colorSleepDeep"], palette.sleepDeep),
          rem: configColor(config, ["sleepRem", "colorSleepRem"], palette.sleepRem),
          core: configColor(config, ["sleepCore", "colorSleepCore"], palette.sleepCore),
          awake: configColor(config, ["sleepAwake", "colorSleepAwake"], palette.sleepAwake)
        },
        activity: {
          move: configColor(config, ["activityMove", "move", "colorActivityMove"], palette.heart),
          exercise: configColor(config, ["activityExercise", "exercise", "colorActivityExercise"], palette.accent),
          stand: configColor(config, ["activityStand", "stand", "colorActivityStand"], palette.secondary)
        }
      },
      maxHeartRate: settings.maxHeartRate,
      mapTilesEnabled: settings.mapTilesEnabled,
      mapTileUrl: settings.mapTileUrl,
      mapTileAttribution: settings.mapTileAttribution
    };
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/dom-utils.ts
  function renderStatBoxes(statsEl, boxes) {
    statsEl.empty();
    boxes.forEach(({ value, label, color }) => {
      const box = statsEl.createDiv({ cls: "health-md-stat-box" });
      const valueEl = box.createDiv({
        cls: "health-md-stat-value",
        text: value
      });
      if (color) {
        valueEl.style.color = color;
      }
      box.createDiv({ cls: "health-md-stat-label", text: label });
    });
  }
  function renderInlineStats(statsEl, stats) {
    statsEl.empty();
    stats.forEach((parts) => {
      const row = statsEl.createSpan();
      parts.forEach((part) => {
        if (part.strong) {
          row.createEl("strong", { text: part.text });
          return;
        }
        row.appendChild(activeDocument.createTextNode(part.text));
      });
    });
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/activity-rings.ts
  var RING_COLORS = {
    move: "#fa114f",
    exercise: "#92e82a",
    stand: "#1eeaef"
  };
  function activityRingColors(theme) {
    var _a;
    return (_a = theme.colors.activity) != null ? _a : RING_COLORS;
  }
  function extractValues(day) {
    var _a, _b, _c, _d;
    const act = day.activity;
    if (!act) return { move: 0, exercise: 0, stand: 0 };
    const steps = (_a = act.steps) != null ? _a : 0;
    const standProxy = Math.min(12, Math.floor(steps / 1e3));
    return {
      move: (_b = act.activeCalories) != null ? _b : 0,
      exercise: (_c = act.exerciseMinutes) != null ? _c : 0,
      stand: (_d = act.standHours) != null ? _d : standProxy
    };
  }
  function drawRingSet(ctx, cx, cy, outerR, stroke, values, goals, theme, hits, day, label) {
    const ringColors = activityRingColors(theme);
    const rings = [
      { key: "move", color: ringColors.move, value: values.move, goal: goals.move, unit: "CAL" },
      { key: "exercise", color: ringColors.exercise, value: values.exercise, goal: goals.exercise, unit: "MIN" },
      { key: "stand", color: ringColors.stand, value: values.stand, goal: goals.stand, unit: "HR" }
    ];
    const gap = Math.max(2, stroke * 0.18);
    rings.forEach((ring, i) => {
      const r = outerR - i * (stroke + gap);
      if (r < stroke) return;
      const progress = ring.goal > 0 ? ring.value / ring.goal : 0;
      ctx.strokeStyle = hexToRgba(ring.color, theme.isDark ? 0.18 : 0.15);
      ctx.lineWidth = stroke;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(cx, cy, r, 0, Math.PI * 2);
      ctx.stroke();
      if (progress <= 0) return;
      const startA = -Math.PI / 2;
      const clamped = Math.min(progress, 1);
      const endA = startA + clamped * Math.PI * 2;
      const grad = ctx.createLinearGradient(cx - r, cy, cx + r, cy);
      grad.addColorStop(0, ring.color);
      grad.addColorStop(1, hexToRgba(ring.color, 0.75));
      ctx.strokeStyle = grad;
      ctx.lineWidth = stroke;
      ctx.lineCap = "round";
      ctx.beginPath();
      ctx.arc(cx, cy, r, startA, endA);
      ctx.stroke();
      if (progress > 1) {
        const excess = Math.min(progress - 1, 1);
        const excessEnd = startA + excess * Math.PI * 2;
        ctx.strokeStyle = hexToRgba(ring.color, 0.55);
        ctx.beginPath();
        ctx.arc(cx, cy, r, startA, excessEnd);
        ctx.stroke();
      }
      hits.add({
        shape: "sector",
        cx,
        cy,
        r0: r - stroke / 2,
        r1: r + stroke / 2,
        a0: 0,
        a1: Math.PI * 2,
        title: `${label} \u2014 ${ring.key.toUpperCase()}`,
        details: [
          { label: "Value", value: `${Math.round(ring.value)} ${ring.unit}` },
          { label: "Goal", value: `${ring.goal} ${ring.unit}` },
          { label: "Progress", value: `${Math.round(progress * 100)}%` }
        ],
        payload: day
      });
    });
  }
  var renderActivityRings = (ctx, data, W, H, config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => d.activity);
    if (!days.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No activity data", W / 2, H / 2);
      return;
    }
    const goals = {
      move: Number(config.moveGoal) || 500,
      exercise: Number(config.exerciseGoal) || 30,
      stand: Number(config.standGoal) || 12
    };
    const ringColors = activityRingColors(theme);
    if (days.length === 1) {
      const day = days[0];
      const values = extractValues(day);
      const cx = W / 2;
      const cy = H / 2;
      const outerR = Math.min(W, H) / 2 - 12;
      const stroke = Math.max(10, outerR * 0.14);
      drawRingSet(ctx, cx, cy, outerR, stroke, values, goals, theme, hits, day, formatDate(day.date));
      const innerR = outerR - 3 * (stroke + stroke * 0.18) - stroke;
      const lines = [
        { text: `${Math.round(values.move)}/${goals.move} CAL`, color: ringColors.move },
        { text: `${Math.round(values.exercise)}/${goals.exercise} MIN`, color: ringColors.exercise },
        { text: `${Math.round(values.stand)}/${goals.stand} HR`, color: ringColors.stand }
      ];
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      const lineH = Math.max(12, innerR * 0.42);
      const fontSize = Math.max(9, Math.min(14, innerR * 0.28));
      ctx.font = `600 ${fontSize}px sans-serif`;
      const startY = cy - (lines.length - 1) * lineH / 2;
      lines.forEach((l, i) => {
        ctx.fillStyle = l.color;
        ctx.fillText(l.text, cx, startY + i * lineH);
      });
      renderStatBoxes(statsEl, [
        {
          value: String(Math.round(values.move)),
          label: `Move / ${goals.move}`,
          color: ringColors.move
        },
        {
          value: String(Math.round(values.exercise)),
          label: `Exercise / ${goals.exercise}`,
          color: ringColors.exercise
        },
        {
          value: String(Math.round(values.stand)),
          label: `Stand / ${goals.stand}`,
          color: ringColors.stand
        }
      ]);
      return;
    }
    const canvas = ctx.canvas;
    const n = days.length;
    const cols = Math.min(n, Math.max(3, Math.round(Math.sqrt(n * (W / H)))));
    const rows = Math.ceil(n / cols);
    const gap = 10;
    const cellW = (W - gap * (cols - 1)) / cols;
    const dateLabelH = 16;
    const cellH = cellW + dateLabelH;
    const neededH = rows * cellH + (rows - 1) * gap + 8;
    if (neededH > H) {
      const dpr = activeWindow.devicePixelRatio || 1;
      canvas.width = W * dpr;
      canvas.height = neededH * dpr;
      canvas.style.width = W + "px";
      canvas.style.height = neededH + "px";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
      ctx.fillStyle = theme.bg;
      ctx.fillRect(0, 0, W, neededH);
    }
    days.forEach((day, idx) => {
      const row = Math.floor(idx / cols);
      const col = idx % cols;
      const x0 = col * (cellW + gap);
      const y0 = row * (cellH + gap);
      const cx = x0 + cellW / 2;
      const cy = y0 + cellW / 2;
      const outerR = cellW / 2 - 4;
      const stroke = Math.max(4, outerR * 0.18);
      const values = extractValues(day);
      drawRingSet(ctx, cx, cy, outerR, stroke, values, goals, theme, hits, day, formatDate(day.date));
      const d = /* @__PURE__ */ new Date(day.date + "T00:00:00");
      const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillStyle = theme.muted;
      ctx.font = "10px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "middle";
      ctx.fillText(label, cx, y0 + cellW + dateLabelH / 2 + 1);
    });
    const totalMove = days.reduce((s, d) => s + extractValues(d).move, 0);
    const totalEx = days.reduce((s, d) => s + extractValues(d).exercise, 0);
    const closedMove = days.filter((d) => extractValues(d).move >= goals.move).length;
    const closedEx = days.filter((d) => extractValues(d).exercise >= goals.exercise).length;
    const closedStand = days.filter((d) => extractValues(d).stand >= goals.stand).length;
    renderStatBoxes(statsEl, [
      {
        value: `${closedMove}/${days.length}`,
        label: "Move closed",
        color: ringColors.move
      },
      {
        value: `${closedEx}/${days.length}`,
        label: "Exercise closed",
        color: ringColors.exercise
      },
      {
        value: `${closedStand}/${days.length}`,
        label: "Stand closed",
        color: ringColors.stand
      },
      {
        value: Math.round(totalMove).toLocaleString(),
        label: "Total CAL"
      },
      {
        value: String(Math.round(totalEx)),
        label: "Total min"
      }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/bar-chart.ts
  var METRICS = {
    steps: {
      label: "Steps",
      unit: "steps",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.steps) != null ? _b : 0;
      },
      formatTotal: (sum) => sum.toLocaleString(),
      formatValue: (v) => Math.round(v).toLocaleString(),
      aggregate: "sum"
    },
    activeCalories: {
      label: "Active Energy",
      unit: "CAL",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.activeCalories) != null ? _b : 0;
      },
      formatTotal: (sum) => Math.round(sum).toLocaleString(),
      formatValue: (v) => `${Math.round(v)}`,
      aggregate: "sum"
    },
    exerciseMinutes: {
      label: "Exercise",
      unit: "min",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.exerciseMinutes) != null ? _b : 0;
      },
      formatTotal: (sum) => `${Math.round(sum)}`,
      formatValue: (v) => `${Math.round(v)}`,
      aggregate: "sum"
    },
    distance: {
      label: "Distance",
      unit: "km",
      color: (t) => t.colors.secondary,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.walkingRunningDistanceKm) != null ? _b : 0;
      },
      formatTotal: (sum) => sum.toFixed(1),
      formatValue: (v) => v.toFixed(2),
      aggregate: "sum"
    },
    sleepHours: {
      label: "Sleep",
      unit: "h",
      color: (t) => t.colors.sleep.rem,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.sleep) == null ? void 0 : _a.totalDuration) != null ? _b : 0) / 3600;
      },
      formatTotal: (sum) => sum.toFixed(1),
      formatValue: (v) => {
        const h = Math.floor(v);
        const m = Math.round((v - h) * 60);
        return `${h}h ${m}m`;
      },
      aggregate: "avg"
    },
    flightsClimbed: {
      label: "Flights Climbed",
      unit: "flights",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return (_b = (_a = d.activity) == null ? void 0 : _a.flightsClimbed) != null ? _b : 0;
      },
      formatTotal: (sum) => `${Math.round(sum)}`,
      formatValue: (v) => `${Math.round(v)}`,
      aggregate: "sum"
    }
  };
  var WEEKDAY_INITIAL = ["S", "M", "T", "W", "T", "F", "S"];
  var renderBarChart = (ctx, data, W, H, config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const metricId = config.metric || "steps";
    const meta = METRICS[metricId];
    if (!meta) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`Unknown metric: ${metricId}`, W / 2, H / 2);
      return;
    }
    const days = data;
    if (!days.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("No data in range", W / 2, H / 2);
      return;
    }
    const values = days.map((d) => meta.extract(d));
    const n = values.length;
    const max = Math.max(...values, 0);
    const nonZero = values.filter((v) => v > 0);
    const total = values.reduce((s, v) => s + v, 0);
    const average = nonZero.length ? total / nonZero.length : 0;
    const goal = config.goal != null ? Number(config.goal) : void 0;
    const showAverage = config.showAverage === void 0 || config.showAverage === "true" || config.showAverage === 1 || config.showAverage === "1";
    const chartEffectiveMax = goal && goal > max ? goal : max;
    const denom = chartEffectiveMax > 0 ? chartEffectiveMax : 1;
    const kpiH = 46;
    const axisH = 18;
    const padT = 8;
    const padB = axisH + 8;
    const padL = 16;
    const padR = 36;
    const plotTop = padT + kpiH;
    const plotH = H - plotTop - padB;
    const headline = meta.aggregate === "sum" ? meta.formatTotal(total) : meta.formatValue(average);
    const subtitle = `${formatDate(days[0].date)} \u2013 ${formatDate(days[n - 1].date)}`;
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = theme.fg;
    ctx.font = "600 22px sans-serif";
    const headlineMetrics = ctx.measureText(headline);
    ctx.fillText(headline, padL, padT + 22);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText(` ${meta.unit}`, padL + headlineMetrics.width + 2, padT + 22);
    ctx.fillText(subtitle, padL, padT + 40);
    const accent = meta.color(theme);
    if (chartEffectiveMax > 0) {
      ctx.fillStyle = theme.muted;
      ctx.font = "10px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "top";
      ctx.fillText(meta.formatValue(chartEffectiveMax), W - 4, plotTop);
    }
    if (showAverage && average > 0 && chartEffectiveMax > 0) {
      const y = plotTop + plotH - average / denom * plotH;
      ctx.save();
      ctx.strokeStyle = hexToRgba(theme.fg, 0.4);
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(plotTop + 10, Math.min(plotTop + plotH - 6, y));
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(`avg ${meta.formatValue(average)}`, W - padR - 4, labelY);
    }
    if (goal && chartEffectiveMax > 0) {
      const y = plotTop + plotH - goal / denom * plotH;
      ctx.save();
      ctx.strokeStyle = hexToRgba(accent, 0.8);
      ctx.lineWidth = 1;
      ctx.setLineDash([2, 3]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(plotTop + 10, Math.min(plotTop + plotH - 6, y));
      ctx.fillStyle = accent;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(`goal ${meta.formatValue(goal)}`, padL + 2, labelY);
    }
    const chartW = W - padL - padR;
    const slot = chartW / n;
    const barW = Math.max(3, Math.min(slot * 0.72, 28));
    const cornerR = Math.min(barW / 2, 6);
    const highlightIdx = n - 1;
    for (let i = 0; i < n; i++) {
      const v = values[i];
      const x = padL + i * slot + (slot - barW) / 2;
      const isHighlight = i === highlightIdx;
      const h = v / denom * plotH;
      const y = plotTop + plotH - h;
      if (h <= 0.5) {
        ctx.fillStyle = hexToRgba(accent, 0.12);
        ctx.beginPath();
        ctx.roundRect(x, plotTop + plotH - 2, barW, 2, 1);
        ctx.fill();
      } else {
        ctx.fillStyle = isHighlight ? accent : hexToRgba(accent, 0.35);
        ctx.beginPath();
        ctx.roundRect(x, y, barW, h, [cornerR, cornerR, 0, 0]);
        ctx.fill();
      }
      hits.add({
        shape: "rect",
        x: padL + i * slot,
        y: plotTop,
        w: slot,
        h: plotH + axisH,
        title: formatDate(days[i].date),
        details: [
          { label: meta.label, value: `${meta.formatValue(v)} ${meta.unit}` }
        ],
        payload: days[i]
      });
    }
    ctx.fillStyle = theme.muted;
    ctx.font = "10px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    if (n <= 7) {
      for (let i = 0; i < n; i++) {
        const d = /* @__PURE__ */ new Date(days[i].date + "T00:00:00");
        const ch = WEEKDAY_INITIAL[d.getDay()];
        const cx = padL + i * slot + slot / 2;
        ctx.fillStyle = i === highlightIdx ? theme.fg : theme.muted;
        ctx.fillText(ch, cx, plotTop + plotH + 4);
      }
    } else {
      const maxLabels = Math.max(2, Math.floor(plotW / 72));
      const labelStep = Math.max(1, Math.ceil(n / maxLabels));
      for (let i = 0; i < n; i++) {
        if (i % labelStep !== 0 && i !== n - 1) continue;
        const d = /* @__PURE__ */ new Date(days[i].date + "T00:00:00");
        const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
        const cx = padL + i * slot + slot / 2;
        ctx.fillStyle = i === highlightIdx ? theme.fg : theme.muted;
        ctx.fillText(label, cx, plotTop + plotH + 4);
      }
    }
    const bestIdx = values.reduce(
      (best2, v, i) => v > values[best2] ? i : best2,
      0
    );
    const best = values[bestIdx];
    const bestLabel = (/* @__PURE__ */ new Date(days[bestIdx].date + "T00:00:00")).toLocaleDateString(
      "en-US",
      { month: "short", day: "numeric" }
    );
    renderStatBoxes(statsEl, [
      {
        value: meta.aggregate === "sum" ? meta.formatTotal(total) : meta.formatValue(total),
        label: `Total ${meta.unit}`
      },
      { value: meta.formatValue(average), label: "Daily avg" },
      { value: meta.formatValue(best), label: `Best (${bestLabel})` }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/range-chart-core.ts
  function renderRangeChart(ctx, data, W, H, theme, statsEl, hits, spec) {
    var _a, _b, _c, _d, _e, _f;
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const points = data.map((d) => {
      const v = spec.extract(d);
      return v ? { day: d, date: d.date, ...v } : null;
    });
    const present = points.filter((p) => p !== null);
    if (!present.length) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`No ${spec.label.toLowerCase()} data`, W / 2, H / 2);
      return;
    }
    const padL = (_a = spec.padL) != null ? _a : 36;
    const padR = 16, padT = 14, padB = 24;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const observedMin = Math.min(...present.map((p) => p.min));
    const observedMax = Math.max(...present.map((p) => p.max));
    const { yMin, yMax, gridStep } = spec.yAxis({ min: observedMin, max: observedMax });
    const yRange = yMax - yMin || 1;
    const n = points.length;
    const xFor = (i) => padL + (n === 1 ? plotW2 / 2 : i / (n - 1) * plotW2);
    const yFor = (v) => padT + plotH - (v - yMin) / yRange * plotH;
    if (spec.warn) {
      ctx.fillStyle = hexToRgba(spec.warn.color, theme.isDark ? 0.12 : 0.08);
      if (spec.warn.lo != null) {
        const yThreshold = yFor(spec.warn.lo);
        ctx.fillRect(padL, yThreshold, plotW2, padT + plotH - yThreshold);
      }
      if (spec.warn.hi != null) {
        const yThreshold = yFor(spec.warn.hi);
        ctx.fillRect(padL, padT, plotW2, yThreshold - padT);
      }
    }
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.lineWidth = 1;
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "right";
    ctx.textBaseline = "middle";
    const startGrid = Math.ceil(yMin / gridStep) * gridStep;
    for (let v = startGrid; v <= yMax; v += gridStep) {
      const y = yFor(v);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.fillText(spec.formatAxisLabel(v), padL - 4, y);
    }
    if (spec.warn) {
      const thresholdV = (_b = spec.warn.lo) != null ? _b : spec.warn.hi;
      const y = yFor(thresholdV);
      ctx.save();
      ctx.strokeStyle = hexToRgba(spec.warn.color, 0.55);
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 3]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(padT + 10, Math.min(padT + plotH - 6, y));
      ctx.fillStyle = spec.warn.color;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(spec.warn.note, padL + 4, labelY);
    }
    if (spec.overlays) {
      spec.overlays({ ctx, data, yFor, yMin, yMax, padL, padR, W });
    }
    const capW = Math.max(4, Math.min(10, plotW2 / Math.max(1, n) * 0.45));
    const capRadius = capW / 2;
    const avgDotInnerLight = (_c = spec.avgDotInnerLightFill) != null ? _c : "#000";
    points.forEach((p, i) => {
      if (!p) return;
      const x = xFor(i);
      const yTop = yFor(p.max);
      const yBot = yFor(p.min);
      const h = Math.max(capW, yBot - yTop);
      const grad = ctx.createLinearGradient(0, yTop, 0, yTop + h);
      grad.addColorStop(0, hexToRgba(spec.capsuleColor, 1));
      grad.addColorStop(1, hexToRgba(spec.capsuleColor, 0.55));
      ctx.fillStyle = grad;
      ctx.beginPath();
      ctx.roundRect(x - capW / 2, yTop, capW, h, capRadius);
      ctx.fill();
      const yAvg = yFor(p.avg);
      ctx.fillStyle = theme.isDark ? "#fff" : avgDotInnerLight;
      ctx.beginPath();
      ctx.arc(x, yAvg, Math.max(2, capW * 0.38), 0, Math.PI * 2);
      ctx.fill();
      ctx.strokeStyle = spec.capsuleColor;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      ctx.arc(x, yAvg, Math.max(2, capW * 0.38), 0, Math.PI * 2);
      ctx.stroke();
      hits.add({
        shape: "rect",
        x: x - capW,
        y: yTop - 4,
        w: capW * 2,
        h: h + 8,
        title: formatDate(p.date),
        details: [
          { label: "Avg", value: `${spec.formatValue(p.avg)} ${spec.unit}` },
          { label: "Min", value: `${spec.formatValue(p.min)} ${spec.unit}` },
          { label: "Max", value: `${spec.formatValue(p.max)} ${spec.unit}` }
        ],
        payload: p.day
      });
    });
    const labelStep = Math.max(1, Math.floor(n / 6));
    ctx.fillStyle = theme.muted;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "center";
    ctx.textBaseline = "top";
    for (let i = 0; i < n; i++) {
      if (i % labelStep !== 0 && i !== n - 1) continue;
      const iso = (_f = (_d = points[i]) == null ? void 0 : _d.date) != null ? _f : (_e = data[i]) == null ? void 0 : _e.date;
      if (!iso) continue;
      const d = /* @__PURE__ */ new Date(iso + "T00:00:00");
      const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillText(label, xFor(i), H - padB + 6);
    }
    const overallMin = Math.min(...present.map((p) => p.min));
    const overallMax = Math.max(...present.map((p) => p.max));
    const overallAvg = present.reduce((s, p) => s + p.avg, 0) / present.length;
    renderStatBoxes(statsEl, [
      {
        value: spec.formatValue(overallMin),
        label: "Lowest",
        color: spec.stats.lowColor
      },
      {
        value: spec.formatValue(overallAvg),
        label: `${spec.label} avg`,
        color: spec.stats.avgColor
      },
      {
        value: spec.formatValue(overallMax),
        label: "Highest",
        color: spec.stats.highColor
      }
    ]);
  }

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/heart-range.ts
  var CAP_COLOR = "#ff3b30";
  var RESTING_COLOR = "#4488ff";
  function extractForMetric(day, metric) {
    if (!day.heart) return null;
    if (metric === "resting") {
      const v = day.heart.restingHeartRate;
      if (v == null || v <= 0) return null;
      return { min: v, max: v, avg: v };
    }
    if (metric === "walking") {
      const v = day.heart.walkingHeartRateAverage;
      if (v == null || v <= 0) return null;
      return { min: v, max: v, avg: v };
    }
    const min = day.heart.heartRateMin;
    const max = day.heart.heartRateMax;
    const avg = day.heart.averageHeartRate;
    if (avg == null || avg <= 0) return null;
    return { min: min > 0 ? min : avg, max: max > 0 ? max : avg, avg };
  }
  function labelFor(m) {
    if (m === "resting") return "Resting HR";
    if (m === "walking") return "Walking HR";
    return "Heart Rate";
  }
  function restingOverlay({ ctx, data, yFor, yMin, yMax, padL, padR, W }) {
    const vals = data.map((d) => {
      var _a;
      return (_a = d.heart) == null ? void 0 : _a.restingHeartRate;
    }).filter((v) => v != null && v > 0);
    if (!vals.length) return;
    const rest = vals.reduce((s, x) => s + x, 0) / vals.length;
    if (rest < yMin || rest > yMax) return;
    const y = yFor(rest);
    ctx.save();
    ctx.strokeStyle = hexToRgba(RESTING_COLOR, 0.55);
    ctx.lineWidth = 1;
    ctx.setLineDash([4, 4]);
    ctx.beginPath();
    ctx.moveTo(padL, y);
    ctx.lineTo(W - padR, y);
    ctx.stroke();
    ctx.restore();
    const labelY = Math.max(yFor(yMax) + 10, Math.min(yFor(yMin) - 6, y));
    ctx.fillStyle = RESTING_COLOR;
    ctx.font = "9px sans-serif";
    ctx.textAlign = "left";
    ctx.textBaseline = "middle";
    ctx.fillText(`resting ~${Math.round(rest)}`, padL + 4, labelY);
  }
  var renderHeartRange = (ctx, data, W, H, config, theme, statsEl, hits) => {
    const metric = config.metric || "heart-rate";
    const spec = {
      label: labelFor(metric),
      unit: "bpm",
      capsuleColor: CAP_COLOR,
      padL: 36,
      avgDotInnerLightFill: "#1a0000",
      extract: (d) => extractForMetric(d, metric),
      yAxis: ({ min, max }) => {
        const yMin = Math.max(0, Math.floor((min - 20) / 10) * 10);
        const yMax = Math.ceil((max + 20) / 10) * 10;
        const range = yMax - yMin || 1;
        return { yMin, yMax, gridStep: range > 120 ? 40 : 20 };
      },
      formatAxisLabel: (v) => String(v),
      formatValue: (v) => String(Math.round(v)),
      stats: { lowColor: RESTING_COLOR, avgColor: CAP_COLOR, highColor: CAP_COLOR },
      overlays: metric === "heart-rate" ? restingOverlay : void 0
    };
    renderRangeChart(ctx, data, W, H, theme, statsEl, hits, spec);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/hrv-trend.ts
  var renderHrvTrend = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter(
      (d) => d.heart && (d.heart.hrv != null || d.heart.hrvSamples && d.heart.hrvSamples.length > 0)
    );
    if (!days.length) return;
    const padL = 36, padR = 16, padT = 16, padB = 28;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const values = days.map((d) => {
      var _a;
      const heart = d.heart;
      if (!heart) return 0;
      if (heart.hrv != null) return heart.hrv;
      const samples = (_a = heart.hrvSamples) != null ? _a : [];
      return samples.reduce((s, x) => s + x.value, 0) / samples.length;
    });
    const minVal = Math.min(...values);
    const maxVal = Math.max(...values);
    const range = maxVal - minVal || 1;
    const xFor = (i) => padL + i / (days.length - 1 || 1) * plotW2;
    const yFor = (v) => padT + plotH - (v - minVal) / range * plotH;
    const gridCount = 4;
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.lineWidth = 1;
    for (let g = 0; g <= gridCount; g++) {
      const y = padT + g / gridCount * plotH;
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      const label = Math.round(maxVal - g / gridCount * range);
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.fillText(String(label), padL - 4, y + 3);
    }
    const grad = ctx.createLinearGradient(0, padT, 0, padT + plotH);
    grad.addColorStop(0, hexToRgba(theme.colors.secondary, 0.35));
    grad.addColorStop(1, hexToRgba(theme.colors.secondary, 0.02));
    ctx.beginPath();
    ctx.moveTo(xFor(0), padT + plotH);
    ctx.lineTo(xFor(0), yFor(values[0]));
    for (let i = 1; i < days.length; i++) {
      const x0 = xFor(i - 1), y0 = yFor(values[i - 1]);
      const x1 = xFor(i), y1 = yFor(values[i]);
      const mx = (x0 + x1) / 2;
      ctx.bezierCurveTo(mx, y0, mx, y1, x1, y1);
    }
    ctx.lineTo(xFor(days.length - 1), padT + plotH);
    ctx.closePath();
    ctx.fillStyle = grad;
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(xFor(0), yFor(values[0]));
    for (let i = 1; i < days.length; i++) {
      const x0 = xFor(i - 1), y0 = yFor(values[i - 1]);
      const x1 = xFor(i), y1 = yFor(values[i]);
      const mx = (x0 + x1) / 2;
      ctx.bezierCurveTo(mx, y0, mx, y1, x1, y1);
    }
    ctx.strokeStyle = hexToRgba(theme.colors.secondary, 0.9);
    ctx.lineWidth = 1.5;
    ctx.lineJoin = "round";
    ctx.stroke();
    days.forEach((day, i) => {
      var _a, _b;
      const x = xFor(i);
      const y = yFor(values[i]);
      ctx.beginPath();
      ctx.arc(x, y, 3.5, 0, Math.PI * 2);
      ctx.fillStyle = theme.colors.secondary;
      ctx.fill();
      hits.add({
        shape: "circle",
        cx: x,
        cy: y,
        r: 10,
        title: formatDate(day.date),
        details: [
          { label: "HRV", value: `${values[i].toFixed(1)} ms` },
          ...((_a = day.heart) == null ? void 0 : _a.restingHeartRate) ? [{ label: "Resting HR", value: `${day.heart.restingHeartRate} bpm` }] : [],
          ...((_b = day.heart) == null ? void 0 : _b.averageHeartRate) ? [{ label: "Avg HR", value: `${Math.round(day.heart.averageHeartRate)} bpm` }] : []
        ],
        payload: day
      });
    });
    const labelStep = Math.max(1, Math.floor(days.length / 5));
    ctx.fillStyle = theme.muted;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "center";
    days.forEach((day, i) => {
      if (i % labelStep !== 0 && i !== days.length - 1) return;
      const d = /* @__PURE__ */ new Date(day.date + "T00:00:00");
      const label = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillText(label, xFor(i), H - 6);
    });
    const avg = values.reduce((s, v) => s + v, 0) / values.length;
    renderInlineStats(statsEl, [
      [
        { text: "Avg HRV " },
        { text: `${avg.toFixed(1)} ms`, strong: true }
      ],
      [
        { text: "Min " },
        { text: minVal.toFixed(1), strong: true }
      ],
      [
        { text: "Max " },
        { text: maxVal.toFixed(1), strong: true }
      ]
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/oxygen-range.ts
  function specFor(metric) {
    if (metric === "respiratory-rate") {
      return {
        label: "Respiratory Rate",
        unit: "brpm",
        capsuleColor: "#3bb2c1",
        padL: 40,
        avgDotInnerLightFill: "#0a1a22",
        extract: (d) => {
          var _a, _b, _c;
          const v = d.vitals;
          if (!v) return null;
          const avg = (_a = v.respiratoryRateAvg) != null ? _a : v.respiratoryRate;
          if (avg == null || avg <= 0) return null;
          return { min: (_b = v.respiratoryRateMin) != null ? _b : avg, max: (_c = v.respiratoryRateMax) != null ? _c : avg, avg };
        },
        yAxis: ({ min, max }) => ({
          yMin: Math.min(10, Math.floor(min - 1)),
          yMax: Math.max(25, Math.ceil(max + 1)),
          gridStep: 5
        }),
        formatAxisLabel: (v) => String(v),
        formatValue: (v) => v.toFixed(1),
        warn: { hi: 20, color: "#ff3b30", note: "Elevated >20 brpm" },
        stats: { lowColor: "#3bb2c1", avgColor: "#3bb2c1", highColor: "#3bb2c1" }
      };
    }
    return {
      label: "Blood Oxygen",
      unit: "%",
      capsuleColor: "#1eeaef",
      padL: 40,
      avgDotInnerLightFill: "#0a1a22",
      extract: (d) => {
        var _a, _b, _c;
        const v = d.vitals;
        if (!v) return null;
        const avg = (_a = v.bloodOxygenAvg) != null ? _a : v.bloodOxygenPercent;
        if (avg == null || avg <= 0) return null;
        return { min: (_b = v.bloodOxygenMin) != null ? _b : avg, max: (_c = v.bloodOxygenMax) != null ? _c : avg, avg };
      },
      yAxis: ({ min, max }) => ({
        yMin: Math.min(90, Math.floor(min - 1)),
        yMax: Math.max(100, Math.ceil(max + 1)),
        gridStep: 2
      }),
      formatAxisLabel: (v) => String(v),
      formatValue: (v) => v.toFixed(1),
      warn: { lo: 95, color: "#ff3b30", note: "Low SpO\u2082 <95%" },
      stats: { lowColor: "#1eeaef", avgColor: "#1eeaef", highColor: "#1eeaef" }
    };
  }
  var renderOxygenRange = (ctx, data, W, H, config, theme, statsEl, hits) => {
    const metric = config.metric || "blood-oxygen";
    renderRangeChart(ctx, data, W, H, theme, statsEl, hits, specFor(metric));
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/sleep-quality-bars.ts
  var renderSleepQualityBars = (ctx, data, W, H, _config, theme, statsEl, hits) => {
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const days = data.filter((d) => d.sleep && d.sleep.totalDuration > 0);
    if (!days.length) return;
    const padL = 40, padR = 16, padT = 20, padB = 28;
    const plotW2 = W - padL - padR;
    const plotH = H - padT - padB;
    const maxTotal = Math.max(...days.map((d) => d.sleep.totalDuration));
    const barW = plotW2 / days.length;
    const gap = Math.max(1, barW * 0.15);
    const maxHours = Math.ceil(maxTotal / 3600);
    const gridStep = maxHours <= 8 ? 2 : 4;
    ctx.strokeStyle = hexToRgba(theme.fg, 0.07);
    ctx.lineWidth = 1;
    for (let h = 0; h <= maxHours; h += gridStep) {
      const y = padT + plotH - h / maxHours * plotH;
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.fillText(`${h}h`, padL - 4, y + 3);
    }
    const legend = [
      { label: "Deep", color: theme.colors.sleep.deep },
      { label: "REM", color: theme.colors.sleep.rem },
      { label: "Core", color: theme.colors.sleep.core },
      { label: "Awake", color: theme.colors.sleep.awake }
    ];
    let lx = padL;
    ctx.font = "8px sans-serif";
    ctx.textAlign = "left";
    for (const item of legend) {
      ctx.fillStyle = item.color;
      ctx.fillRect(lx, padT - 12, 8, 6);
      ctx.fillStyle = theme.muted;
      ctx.fillText(item.label, lx + 10, padT - 7);
      lx += 44;
    }
    const dateLabelStep = days.length <= 14 ? 1 : Math.max(1, Math.ceil(days.length / 6));
    days.forEach((day, i) => {
      const sl = day.sleep;
      const x = padL + i * barW + gap / 2;
      const bw = barW - gap;
      const segments = [
        { secs: sl.deepSleep || 0, color: theme.colors.sleep.deep, label: "Deep" },
        { secs: sl.remSleep || 0, color: theme.colors.sleep.rem, label: "REM" },
        { secs: sl.coreSleep || 0, color: theme.colors.sleep.core, label: "Core" },
        { secs: sl.awakeTime || 0, color: theme.colors.sleep.awake, label: "Awake" }
      ].filter((s) => s.secs > 0);
      let stackY = padT + plotH;
      segments.forEach(({ secs, color, label }, si) => {
        const segH = secs / maxTotal * plotH;
        stackY -= segH;
        const isTop = si === segments.length - 1;
        const r = isTop ? Math.min(3, bw / 4) : 0;
        ctx.fillStyle = hexToRgba(color, 0.85);
        ctx.beginPath();
        if (isTop) {
          ctx.roundRect(x, stackY, bw, segH, [r, r, 0, 0]);
        } else {
          ctx.rect(x, stackY, bw, segH);
        }
        ctx.fill();
        if (segH > 14 && bw > 28) {
          ctx.fillStyle = hexToRgba(theme.bg, 0.7);
          ctx.font = "7px sans-serif";
          ctx.textAlign = "center";
          ctx.fillText(label, x + bw / 2, stackY + segH / 2 + 2.5);
        }
      });
      if (i % dateLabelStep === 0 || i === days.length - 1) {
        const d = /* @__PURE__ */ new Date(day.date + "T00:00:00");
        const lbl = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
        ctx.fillStyle = theme.muted;
        ctx.font = "8px sans-serif";
        ctx.textAlign = "center";
        ctx.fillText(lbl, x + bw / 2, H - 6);
      }
      const barTop = padT + plotH - sl.totalDuration / maxTotal * plotH;
      hits.add({
        shape: "rect",
        x,
        y: barTop,
        w: bw,
        h: plotH - (barTop - padT),
        title: formatDate(day.date),
        details: [
          { label: "Total", value: formatDuration(sl.totalDuration) },
          ...sl.deepSleep ? [{ label: "Deep", value: formatDuration(sl.deepSleep) }] : [],
          ...sl.remSleep ? [{ label: "REM", value: formatDuration(sl.remSleep) }] : [],
          ...sl.coreSleep ? [{ label: "Core", value: formatDuration(sl.coreSleep) }] : [],
          ...sl.awakeTime ? [{ label: "Awake", value: formatDuration(sl.awakeTime) }] : [],
          ...sl.bedtime ? [{
            label: "Bedtime",
            value: new Date(sl.bedtime).toLocaleTimeString("en-US", {
              hour: "numeric",
              minute: "2-digit"
            })
          }] : []
        ],
        payload: day
      });
    });
    const avgTotal = days.reduce((s, d) => s + d.sleep.totalDuration, 0) / days.length;
    const avgDeep = days.reduce((s, d) => s + (d.sleep.deepSleep || 0), 0) / days.length;
    const avgRem = days.reduce((s, d) => s + (d.sleep.remSleep || 0), 0) / days.length;
    renderInlineStats(statsEl, [
      [
        { text: "Avg sleep " },
        { text: formatDuration(avgTotal), strong: true }
      ],
      [
        { text: "Avg deep " },
        { text: formatDuration(avgDeep), strong: true }
      ],
      [
        { text: "Avg REM " },
        { text: formatDuration(avgRem), strong: true }
      ]
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/sleep-schedule.ts
  var DAY_MS = 864e5;
  function parseWindow(str) {
    const clock = parseClockTime(str);
    if (!clock) return { h: 0, m: 0 };
    return { h: clock.h, m: clock.m };
  }
  function parseClockTime(raw) {
    var _a, _b;
    const value = raw == null ? void 0 : raw.trim();
    if (!value) return null;
    let m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?$/.exec(value);
    if (m) {
      const h = Number(m[1]);
      const min = Number(m[2]);
      const sec = Number((_a = m[3]) != null ? _a : 0);
      if (h <= 23 && min <= 59 && sec <= 59) return { h, m: min, s: sec };
      return null;
    }
    m = /^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*([ap])\.?m\.?$/i.exec(value);
    if (m) {
      let h = Number(m[1]);
      const min = Number(m[2]);
      const sec = Number((_b = m[3]) != null ? _b : 0);
      if (h < 1 || h > 12 || min > 59 || sec > 59) return null;
      const meridiem = m[4].toLowerCase();
      if (meridiem === "p" && h !== 12) h += 12;
      if (meridiem === "a" && h === 12) h = 0;
      return { h, m: min, s: sec };
    }
    return null;
  }
  function clockMsOnDate(dateIso, clock) {
    return (/* @__PURE__ */ new Date(
      `${dateIso}T${String(clock.h).padStart(2, "0")}:${String(clock.m).padStart(2, "0")}:${String(clock.s).padStart(2, "0")}`
    )).getTime();
  }
  function parseAbsoluteMs(raw) {
    if (!(raw == null ? void 0 : raw.trim())) return NaN;
    return Date.parse(raw.trim());
  }
  function resolveExplicitBedWake(night, sleep) {
    var _a, _b, _c, _d;
    const bedRaw = (_b = (_a = sleep.bedtimeISO) != null ? _a : sleep.sessionStart) != null ? _b : sleep.bedtime;
    const wakeRaw = (_d = (_c = sleep.wakeTimeISO) != null ? _c : sleep.sessionEnd) != null ? _d : sleep.wakeTime;
    if (!bedRaw || !wakeRaw) return null;
    const bedClock = parseClockTime(bedRaw);
    const wakeClock = parseClockTime(wakeRaw);
    let bedMs = bedClock ? clockMsOnDate(night.date, bedClock) : parseAbsoluteMs(bedRaw);
    let wakeMs = wakeClock ? clockMsOnDate(night.date, wakeClock) : parseAbsoluteMs(wakeRaw);
    if (!isFinite(bedMs) || !isFinite(wakeMs)) return null;
    if (wakeMs <= bedMs && (bedClock || wakeClock)) wakeMs += DAY_MS;
    if (wakeMs <= bedMs) return null;
    return { bedMs, wakeMs };
  }
  function resolveStageBedWake(sleep) {
    var _a;
    const stages = (_a = sleep.sleepStages) != null ? _a : [];
    let bedMs = Infinity;
    let wakeMs = -Infinity;
    for (const stage of stages) {
      const startMs = Date.parse(stage.startDate);
      const endMs = Date.parse(stage.endDate);
      if (isFinite(startMs) && startMs < bedMs) bedMs = startMs;
      if (isFinite(endMs) && endMs > wakeMs) wakeMs = endMs;
    }
    if (!isFinite(bedMs) || !isFinite(wakeMs) || wakeMs <= bedMs) return null;
    return { bedMs, wakeMs };
  }
  function resolveBedWake(night) {
    var _a;
    const sleep = night.sleep;
    if (!sleep) return null;
    return (_a = resolveExplicitBedWake(night, sleep)) != null ? _a : resolveStageBedWake(sleep);
  }
  function formatHour(ms) {
    return new Date(ms).toLocaleTimeString("en-US", {
      hour: "numeric",
      minute: "2-digit"
    });
  }
  function hourLabel(h) {
    const hr = (h % 24 + 24) % 24;
    if (hr === 0) return "12A";
    if (hr === 12) return "12P";
    if (hr < 12) return `${hr}A`;
    return `${hr - 12}P`;
  }
  function localDateIso(ms) {
    const d = new Date(ms);
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  }
  function addDaysIso(dateIso, days) {
    const d = /* @__PURE__ */ new Date(`${dateIso}T00:00:00`);
    d.setDate(d.getDate() + days);
    return localDateIso(d.getTime());
  }
  var renderSleepSchedule = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b, _c;
    const canvas = ctx.canvas;
    const sleepGoalHours = Number(config.sleepGoal) || 8;
    const windowStart = parseWindow(String(config.windowStart || "18:00"));
    const windowEnd = parseWindow(String(config.windowEnd || "10:00"));
    const nights = [];
    for (const d of data) {
      if (!d.sleep) continue;
      const stageCount = (_b = (_a = d.sleep.sleepStages) == null ? void 0 : _a.length) != null ? _b : 0;
      const totalDuration = (_c = d.sleep.totalDuration) != null ? _c : 0;
      if (!(stageCount > 0 || totalDuration > 0)) continue;
      const bw = resolveBedWake(d);
      if (!bw) continue;
      nights.push({
        date: d.date,
        day: d,
        bedMs: bw.bedMs,
        wakeMs: bw.wakeMs,
        totalSeconds: totalDuration || (bw.wakeMs - bw.bedMs) / 1e3
      });
    }
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    if (!nights.length) {
      ctx.fillStyle = theme.muted;
      ctx.textAlign = "center";
      ctx.font = "12px sans-serif";
      ctx.fillText("No sleep schedule data", W / 2, H / 2 - 8);
      ctx.font = "10px sans-serif";
      ctx.fillText("Requires bedtime/wake or stage timestamps", W / 2, H / 2 + 10);
      return;
    }
    const rowH = 26;
    const rowGap = 6;
    const padT = 10;
    const axisH = 34;
    const gutterW = 104;
    const rightPad = 16;
    const barAreaX = gutterW;
    const barAreaW = W - gutterW - rightPad;
    const neededH = padT + nights.length * (rowH + rowGap) + axisH + 8;
    if (neededH !== H) {
      const dpr = activeWindow.devicePixelRatio || 1;
      canvas.width = W * dpr;
      canvas.height = neededH * dpr;
      canvas.style.width = W + "px";
      canvas.style.height = neededH + "px";
      ctx.setTransform(1, 0, 0, 1, 0, 0);
      ctx.scale(dpr, dpr);
      ctx.fillStyle = theme.bg;
      ctx.fillRect(0, 0, W, neededH);
    }
    function windowBoundsFor(dateIso) {
      const startMs = (/* @__PURE__ */ new Date(`${dateIso}T${String(windowStart.h).padStart(2, "0")}:${String(windowStart.m).padStart(2, "0")}:00`)).getTime();
      const base = (/* @__PURE__ */ new Date(`${dateIso}T00:00:00`)).getTime();
      let endMs = base + 864e5 + windowEnd.h * 36e5 + windowEnd.m * 6e4;
      if (endMs <= startMs) endMs += 864e5;
      return { startMs, endMs };
    }
    function windowBoundsForNight(night) {
      const bedDate = localDateIso(night.bedMs);
      const wakeDate = localDateIso(night.wakeMs);
      const candidates = Array.from(/* @__PURE__ */ new Set([
        addDaysIso(night.date, -1),
        night.date,
        addDaysIso(night.date, 1),
        addDaysIso(bedDate, -1),
        bedDate,
        addDaysIso(bedDate, 1),
        addDaysIso(wakeDate, -1),
        wakeDate
      ]));
      let best = windowBoundsFor(night.date);
      let bestOverlap = -1;
      let bestDistance = Infinity;
      for (const dateIso of candidates) {
        const bounds = windowBoundsFor(dateIso);
        const overlap = Math.max(
          0,
          Math.min(night.wakeMs, bounds.endMs) - Math.max(night.bedMs, bounds.startMs)
        );
        const distance = Math.abs(night.bedMs - bounds.startMs);
        if (overlap > bestOverlap || overlap === bestOverlap && distance < bestDistance) {
          best = bounds;
          bestOverlap = overlap;
          bestDistance = distance;
        }
      }
      return best;
    }
    const nightBounds = nights.map(windowBoundsForNight);
    const sampleBounds = nightBounds[0];
    const windowSpan = sampleBounds.endMs - sampleBounds.startMs;
    const windowHours = windowSpan / 36e5;
    const plotTop = padT;
    const plotH = nights.length * (rowH + rowGap) - rowGap;
    const bgGrad = ctx.createLinearGradient(barAreaX, 0, barAreaX + barAreaW, 0);
    const cSunset = theme.isDark ? "#3a1a3a" : "#f5dccc";
    const cNight = theme.isDark ? "#0b0b22" : "#d6dbe8";
    const cSunrise = theme.isDark ? "#3a2a14" : "#fee7c8";
    bgGrad.addColorStop(0, cSunset);
    bgGrad.addColorStop(0.45, cNight);
    bgGrad.addColorStop(0.65, cNight);
    bgGrad.addColorStop(1, cSunrise);
    ctx.fillStyle = bgGrad;
    ctx.beginPath();
    ctx.roundRect(barAreaX, plotTop, barAreaW, plotH, 8);
    ctx.fill();
    ctx.strokeStyle = hexToRgba(theme.fg, 0.08);
    ctx.lineWidth = 1;
    const startHour = windowStart.h;
    const numTicks = Math.max(2, Math.round(windowHours / 2));
    for (let k = 0; k <= numTicks; k++) {
      const frac = k / numTicks;
      const x = barAreaX + frac * barAreaW;
      ctx.beginPath();
      ctx.moveTo(x, plotTop);
      ctx.lineTo(x, plotTop + plotH);
      ctx.stroke();
      const h = startHour + frac * windowHours;
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(hourLabel(h), x, plotTop + plotH + 4);
    }
    const meanBedOffset = nights.reduce((s, nn, i) => {
      const wb = nightBounds[i];
      return s + (nn.bedMs - wb.startMs);
    }, 0) / nights.length;
    const goalSpan = sleepGoalHours * 36e5;
    const goalStartFrac = meanBedOffset / windowSpan;
    const goalEndFrac = (meanBedOffset + goalSpan) / windowSpan;
    if (goalEndFrac > 0 && goalStartFrac < 1) {
      const gx0 = barAreaX + Math.max(0, goalStartFrac) * barAreaW;
      const gx1 = barAreaX + Math.min(1, goalEndFrac) * barAreaW;
      ctx.save();
      ctx.strokeStyle = hexToRgba(theme.colors.sleep.rem, 0.8);
      ctx.lineWidth = 1;
      ctx.setLineDash([3, 3]);
      ctx.beginPath();
      ctx.moveTo(gx0, plotTop + plotH + 18);
      ctx.lineTo(gx1, plotTop + plotH + 18);
      ctx.stroke();
      ctx.restore();
      ctx.fillStyle = theme.colors.sleep.rem;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(`goal ${sleepGoalHours}h`, (gx0 + gx1) / 2, plotTop + plotH + 22);
    }
    nights.forEach((n, i) => {
      const wb = nightBounds[i];
      const y = padT + i * (rowH + rowGap);
      const d = /* @__PURE__ */ new Date(n.date + "T00:00:00");
      const weekday = d.toLocaleDateString("en-US", { weekday: "short" });
      const datepart = d.toLocaleDateString("en-US", { month: "short", day: "numeric" });
      ctx.fillStyle = theme.fg;
      ctx.font = "600 11px sans-serif";
      ctx.textAlign = "left";
      ctx.textBaseline = "middle";
      ctx.fillText(weekday, 10, y + rowH / 2 - 6);
      ctx.fillStyle = theme.muted;
      ctx.font = "10px sans-serif";
      ctx.fillText(datepart, 10, y + rowH / 2 + 7);
      const bedFrac = Math.max(0, Math.min(1, (n.bedMs - wb.startMs) / windowSpan));
      const wakeFrac = Math.max(0, Math.min(1, (n.wakeMs - wb.startMs) / windowSpan));
      if (wakeFrac <= bedFrac) return;
      const bx = barAreaX + bedFrac * barAreaW;
      const bw2 = (wakeFrac - bedFrac) * barAreaW;
      const sleptHours = n.totalSeconds / 3600;
      let barColor = theme.colors.sleep.core;
      if (sleptHours >= sleepGoalHours * 0.95 && sleptHours <= sleepGoalHours * 1.15) {
        barColor = theme.colors.sleep.rem;
      } else if (sleptHours < sleepGoalHours * 0.85) {
        barColor = theme.colors.sleep.awake;
      } else {
        barColor = theme.colors.sleep.deep;
      }
      ctx.fillStyle = hexToRgba(barColor, 0.45);
      ctx.beginPath();
      ctx.roundRect(bx, y + 3, bw2, rowH - 6, 4);
      ctx.fill();
      const bedWindowSec = (n.wakeMs - n.bedMs) / 1e3;
      const asleepFrac = bedWindowSec > 0 ? Math.min(1, n.totalSeconds / bedWindowSec) : 1;
      if (asleepFrac < 1 && asleepFrac > 0) {
        const innerW = bw2 * asleepFrac;
        ctx.fillStyle = barColor;
        ctx.beginPath();
        ctx.roundRect(bx, y + 6, innerW, rowH - 12, 3);
        ctx.fill();
      } else {
        ctx.fillStyle = barColor;
        ctx.beginPath();
        ctx.roundRect(bx, y + 6, bw2, rowH - 12, 3);
        ctx.fill();
      }
      hits.add({
        shape: "rect",
        x: bx,
        y,
        w: bw2,
        h: rowH,
        title: formatDate(n.date),
        details: [
          { label: "Bedtime", value: formatHour(n.bedMs) },
          { label: "Wake", value: formatHour(n.wakeMs) },
          { label: "Total sleep", value: formatDuration(n.totalSeconds) },
          { label: "Goal", value: `${sleepGoalHours}h` }
        ],
        payload: n.day
      });
    });
    const bedOffsets = nights.map((n, i) => {
      const wb = nightBounds[i];
      return (n.bedMs - wb.startMs) / 36e5;
    });
    const wakeOffsets = nights.map((n, i) => {
      const wb = nightBounds[i];
      return (n.wakeMs - wb.startMs) / 36e5;
    });
    const meanBedH = bedOffsets.reduce((s, v) => s + v, 0) / bedOffsets.length;
    const meanWakeH = wakeOffsets.reduce((s, v) => s + v, 0) / wakeOffsets.length;
    const variance = bedOffsets.reduce((s, v) => s + (v - meanBedH) ** 2, 0) / bedOffsets.length;
    const stdev = Math.sqrt(variance);
    function offsetToHourStr(offsetH) {
      const abs = new Date(nightBounds[0].startMs + offsetH * 36e5);
      return abs.toLocaleTimeString("en-US", { hour: "numeric", minute: "2-digit" });
    }
    const consistencyLabel = stdev < 0.5 ? "Very consistent" : stdev < 1 ? "Consistent" : stdev < 2 ? "Variable" : "Irregular";
    renderStatBoxes(statsEl, [
      { value: offsetToHourStr(meanBedH), label: "Avg bedtime" },
      { value: offsetToHourStr(meanWakeH), label: "Avg wake" },
      { value: consistencyLabel, label: `\xB1${stdev.toFixed(1)}h stdev` }
    ]);
  };

  // ../../obsidian-plugin-hub/obsidian-health-md/src/visualizations/weekday-average.ts
  var METRICS2 = {
    steps: {
      label: "Steps",
      unit: "steps",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.steps) != null ? _b : 0) > 0 ? d.activity.steps : null;
      },
      format: (v) => Math.round(v).toLocaleString()
    },
    activeCalories: {
      label: "Active Calories",
      unit: "CAL",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.activeCalories) != null ? _b : 0) > 0 ? d.activity.activeCalories : null;
      },
      format: (v) => `${Math.round(v)}`
    },
    exerciseMinutes: {
      label: "Exercise",
      unit: "min",
      color: (t) => t.colors.accent,
      extract: (d) => {
        var _a, _b;
        return ((_b = (_a = d.activity) == null ? void 0 : _a.exerciseMinutes) != null ? _b : 0) > 0 ? d.activity.exerciseMinutes : null;
      },
      format: (v) => `${Math.round(v)}`
    },
    sleepHours: {
      label: "Sleep",
      unit: "h",
      color: (t) => t.colors.sleep.rem,
      extract: (d) => {
        var _a;
        const v = (_a = d.sleep) == null ? void 0 : _a.totalDuration;
        return v != null && v > 0 ? v / 3600 : null;
      },
      format: (v) => {
        const h = Math.floor(v);
        const m = Math.round((v - h) * 60);
        return `${h}h ${m}m`;
      }
    },
    heartRate: {
      label: "Avg HR",
      unit: "bpm",
      color: (t) => t.colors.heart,
      extract: (d) => {
        var _a;
        const v = (_a = d.heart) == null ? void 0 : _a.averageHeartRate;
        return v != null && v > 0 ? v : null;
      },
      format: (v) => `${Math.round(v)}`
    },
    hrv: {
      label: "HRV",
      unit: "ms",
      color: (t) => t.colors.secondary,
      extract: (d) => {
        var _a, _b;
        if (((_a = d.heart) == null ? void 0 : _a.hrv) != null) return d.heart.hrv;
        const s = (_b = d.heart) == null ? void 0 : _b.hrvSamples;
        if (s && s.length) return s.reduce((acc, x) => acc + x.value, 0) / s.length;
        return null;
      },
      format: (v) => v.toFixed(1)
    }
  };
  var renderWeekdayAverage = (ctx, data, W, H, config, theme, statsEl, hits) => {
    var _a, _b;
    ctx.fillStyle = theme.bg;
    ctx.fillRect(0, 0, W, H);
    const metricId = config.metric || "steps";
    const meta = METRICS2[metricId];
    if (!meta) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`Unknown metric: ${metricId}`, W / 2, H / 2);
      return;
    }
    const weekStart = String(config.weekStart || "monday").toLowerCase() === "sunday" ? "sunday" : "monday";
    if (data.length < 7) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText("Weekday averages need at least 7 days of data.", W / 2, H / 2);
      return;
    }
    const buckets = Array.from(
      { length: 7 },
      () => ({ values: [], dates: [] })
    );
    data.forEach((day) => {
      const v = meta.extract(day);
      if (v == null) return;
      const dow = (/* @__PURE__ */ new Date(day.date + "T00:00:00")).getDay();
      buckets[dow].values.push(v);
      buckets[dow].dates.push(day.date);
    });
    const orderIdx = weekStart === "sunday" ? [0, 1, 2, 3, 4, 5, 6] : [1, 2, 3, 4, 5, 6, 0];
    const initials = orderIdx.map((d) => ["S", "M", "T", "W", "T", "F", "S"][d]);
    const avgs = orderIdx.map((dow) => {
      const b = buckets[dow];
      return b.values.length ? b.values.reduce((s, v) => s + v, 0) / b.values.length : null;
    });
    const counts = orderIdx.map((dow) => buckets[dow].values.length);
    const hasAny = avgs.some((a) => a != null);
    if (!hasAny) {
      ctx.fillStyle = theme.muted;
      ctx.font = "12px sans-serif";
      ctx.textAlign = "center";
      ctx.fillText(`No ${meta.label.toLowerCase()} data`, W / 2, H / 2);
      return;
    }
    const maxAvg = Math.max(...avgs.map((a) => a != null ? a : 0));
    const allValues = avgs.filter((a) => a != null);
    const overallMean = allValues.reduce((s, v) => s + v, 0) / allValues.length;
    const totalSamples = counts.reduce((s, c) => s + c, 0);
    const weeksApprox = Math.max(1, Math.round(totalSamples / 7));
    const padT = 14;
    const kpiH = 40;
    const axisH = 18;
    const padL = 16;
    const padR = 16;
    const valueLabelH = 14;
    const plotTop = padT + kpiH;
    const plotBottom = H - axisH - 6;
    const plotH = plotBottom - plotTop - valueLabelH;
    ctx.textAlign = "left";
    ctx.textBaseline = "alphabetic";
    ctx.fillStyle = theme.fg;
    ctx.font = "600 20px sans-serif";
    const headlineText = `${meta.format(overallMean)} ${meta.unit}`;
    ctx.fillText(headlineText, padL, padT + 20);
    ctx.fillStyle = theme.muted;
    ctx.font = "11px sans-serif";
    ctx.fillText(`Avg ${meta.label.toLowerCase()} across ${weeksApprox} week${weeksApprox === 1 ? "" : "s"}`, padL, padT + 38);
    const color = meta.color(theme);
    if (overallMean > 0 && maxAvg > 0) {
      const y = plotTop + valueLabelH + plotH - overallMean / maxAvg * plotH;
      ctx.save();
      ctx.strokeStyle = hexToRgba(theme.fg, 0.45);
      ctx.lineWidth = 1;
      ctx.setLineDash([4, 4]);
      ctx.beginPath();
      ctx.moveTo(padL, y);
      ctx.lineTo(W - padR, y);
      ctx.stroke();
      ctx.restore();
      const labelY = Math.max(plotTop + valueLabelH + 10, Math.min(plotBottom - 8, y));
      ctx.fillStyle = theme.muted;
      ctx.font = "9px sans-serif";
      ctx.textAlign = "right";
      ctx.textBaseline = "middle";
      ctx.fillText(`mean ${meta.format(overallMean)}`, W - padR - 2, labelY);
    }
    let maxIdx = 0;
    for (let i = 1; i < 7; i++) {
      if (((_a = avgs[i]) != null ? _a : 0) > ((_b = avgs[maxIdx]) != null ? _b : 0)) maxIdx = i;
    }
    const chartW = W - padL - padR;
    const slot = chartW / 7;
    const barW = Math.min(46, slot * 0.7);
    const cornerR = Math.min(barW / 2, 8);
    for (let i = 0; i < 7; i++) {
      const v = avgs[i];
      const x = padL + i * slot + (slot - barW) / 2;
      const dow = orderIdx[i];
      const isWeekend = dow === 0 || dow === 6;
      const isMax = i === maxIdx && v != null;
      let fill = hexToRgba(color, 0.55);
      if (isWeekend) fill = hexToRgba(color, 0.4);
      if (isMax) fill = color;
      if (v != null && maxAvg > 0) {
        const h = v / maxAvg * plotH;
        const y = plotTop + valueLabelH + plotH - h;
        ctx.fillStyle = fill;
        ctx.beginPath();
        ctx.roundRect(x, y, barW, h, [cornerR, cornerR, 0, 0]);
        ctx.fill();
        if (slot >= 42) {
          ctx.fillStyle = isMax ? theme.fg : theme.muted;
          ctx.font = isMax ? "600 10px sans-serif" : "10px sans-serif";
          ctx.textAlign = "center";
          ctx.textBaseline = "bottom";
          ctx.fillText(meta.format(v), x + barW / 2, y - 3);
        }
      } else {
        ctx.fillStyle = hexToRgba(color, 0.1);
        ctx.beginPath();
        ctx.roundRect(x, plotBottom - 3, barW, 3, 2);
        ctx.fill();
      }
      ctx.fillStyle = isWeekend ? theme.muted : theme.fg;
      ctx.font = "11px sans-serif";
      ctx.textAlign = "center";
      ctx.textBaseline = "top";
      ctx.fillText(initials[i], x + barW / 2, plotBottom + 4);
      hits.add({
        shape: "rect",
        x: padL + i * slot,
        y: plotTop,
        w: slot,
        // Include the x-axis label area so clicking “Tuesday” behaves the
        // same as clicking the Tuesday bar.
        h: plotBottom + axisH - plotTop,
        title: ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][dow],
        details: v != null ? [
          { label: "Average", value: `${meta.format(v)} ${meta.unit}` },
          { label: "Samples", value: `${counts[i]}` }
        ] : [
          { label: "Status", value: "No data" }
        ],
        payload: buckets[dow].dates
      });
    }
    const bestLabel = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][orderIdx[maxIdx]];
    const worstIdx = avgs.reduce(
      (best, v, i) => {
        var _a2;
        return v != null && (avgs[best] == null || v < ((_a2 = avgs[best]) != null ? _a2 : Infinity)) ? i : best;
      },
      0
    );
    const worstLabel = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][orderIdx[worstIdx]];
    const bestValue = avgs[maxIdx];
    const worstValue = avgs[worstIdx];
    renderStatBoxes(statsEl, [
      { value: meta.format(overallMean), label: "Overall mean" },
      {
        value: bestLabel,
        label: `Best (${bestValue != null ? meta.format(bestValue) : "\u2014"})`
      },
      {
        value: worstLabel,
        label: `Lowest (${worstValue != null ? meta.format(worstValue) : "\u2014"})`
      },
      { value: String(totalSamples), label: "Days sampled" }
    ]);
  };

  // ../../../../../private/var/folders/dj/3srkns7n7qxb2kp1vxb_4xjm0000gn/T/healthmd-viz-bundle-ojpCfX/healthmd-viz-entry.ts
  window.HealthMdPluginVisualizations = {
    source: "obsidian-health-md src/visualizations",
    sourceRepo: "/Users/codybontecou/projects/obsidian-plugin-hub/obsidian-health-md",
    generatedBy: "website/scripts/build-plugin-visualizations.mjs",
    colorSchemes: COLOR_SCHEMES,
    resolveTheme,
    renderers: {
      "activity-rings": renderActivityRings,
      "bar-chart": renderBarChart,
      "heart-range": renderHeartRange,
      "hrv-trend": renderHrvTrend,
      "oxygen-range": renderOxygenRange,
      "sleep-quality-bars": renderSleepQualityBars,
      "sleep-schedule": renderSleepSchedule,
      "weekday-average": renderWeekdayAverage
    }
  };
})();

const config = {
  app: {
    name: "Health.md",
    icon: "screenshots/app-icon.png",
  },

  brand: {
    primary: "#7C3AED",       // brand violet
    secondary: "#4F46E5",     // deep indigo — gradient partner
    background: "#0A0A14",    // near-black with purple tint
    surface: "#1A1530",       // dark card surface
    text: "#FFFFFF",          // white headlines
    textMuted: "#A1A1AA",     // muted labels
    accent: "#A78BFA",        // lighter violet — highlights
  },

  theme: "dark-bold",

  device: {
    color: "black",
  },

  slides: [
    {
      id: "hero",
      layout: "text-top",
      screenshot: "screenshots/screen-export.png",
      label: "YOUR DATA",
      headline: "Your health data.\nUnlocked.",
    },
    {
      id: "metrics",
      layout: "text-top",
      screenshot: "screenshots/screen-metrics.png",
      label: "60+ METRICS",
      headline: "Pick what\nmatters to you.",
      subtext: "Sleep, steps, heart rate — choose exactly what gets exported.",
    },
    {
      id: "obsidian",
      layout: "text-top",
      screenshot: "screenshots/screen-obsidian.png",
      label: "OBSIDIAN SYNC",
      headline: "Health data\nin your vault.",
      subtext: "Write directly to your Obsidian vault. Daily notes, too.",
    },
    {
      id: "automate",
      layout: "text-top",
      screenshot: "screenshots/screen-schedule.png",
      label: "AUTOMATED",
      headline: "Set it once.\nForget it.",
      subtext: "Schedule exports every 15 minutes, hourly, or daily.",
    },
    {
      id: "formats",
      layout: "text-top",
      screenshot: "screenshots/screen-configure.png",
      label: "ANY FORMAT",
      headline: "Markdown, JSON,\nor CSV.",
      subtext: "Your data, in the format your workflow actually uses.",
    },
  ],

  featureGraphic: {
    headline: "Your health data. Your files. Your vault.",
    subtext: "Available on Google Play",
    style: "gradient",
  },

  tablet: {
    enabled: true,
    sizes: ["7-inch", "10-inch"],
  },

  locales: ["en"],
};

(function () {
  var storageKey = "healthmd-theme";
  var themes = ["system", "light", "dark"];
  var labels = {
    system: "Use system theme",
    light: "Use light theme",
    dark: "Use dark theme"
  };
  var root = document.documentElement;

  function normalize(theme) {
    return themes.indexOf(theme) >= 0 ? theme : "system";
  }

  function storedTheme() {
    try {
      return normalize(window.localStorage.getItem(storageKey));
    } catch (_error) {
      return "system";
    }
  }

  function updateControls(theme) {
    var buttons = document.querySelectorAll("[data-theme-option]");
    buttons.forEach(function (button) {
      var active = button.getAttribute("data-theme-option") === theme;
      button.setAttribute("aria-pressed", active ? "true" : "false");
    });
  }

  function applyTheme(theme) {
    var nextTheme = normalize(theme);
    root.setAttribute("data-theme", nextTheme);
    updateControls(nextTheme);
  }

  function setTheme(theme) {
    var nextTheme = normalize(theme);
    try {
      window.localStorage.setItem(storageKey, nextTheme);
    } catch (_error) {
      // Ignore private-mode storage failures; the active page can still switch.
    }
    applyTheme(nextTheme);
  }

  applyTheme(storedTheme());

  window.HealthMdTheme = {
    apply: applyTheme,
    get: storedTheme,
    set: setTheme
  };

  document.addEventListener("DOMContentLoaded", function () {
    updateControls(storedTheme());
    document.querySelectorAll("[data-theme-option]").forEach(function (button) {
      var option = normalize(button.getAttribute("data-theme-option"));
      button.setAttribute("aria-label", labels[option]);
      button.setAttribute("title", labels[option]);
      button.addEventListener("click", function () {
        setTheme(button.getAttribute("data-theme-option"));
      });
    });
  });
})();

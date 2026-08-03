(function () {
  "use strict";

  document.documentElement.classList.add("has-js");

  var reducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var SVG_NAMESPACE = "http://www.w3.org/2000/svg";
  var DEFAULT_MESSAGES = {
    intlLocale: "en-US",
    sampleReady: "Sample file ready",
    sampleTitle: "Health Data Sample",
    sampleDisclaimer: "Sample data only. These values are fictional.",
    metric: "Metric",
    value: "Value",
    date: "Date",
    steps: "Steps",
    stepsUnit: "steps",
    sleep: "Sleep",
    hourShort: "hr",
    minuteShort: "min",
    restingHeartRate: "Resting heart rate",
    heartRateUnit: "bpm",
    walkingDistance: "Walking distance",
    related: "Related",
    healthDashboard: "Health Dashboard",
    emptyFormats: "Choose one or more export formats.",
    downloadNone: "Download samples",
    downloadOne: "Download a sample",
    downloadMany: "Download {count} samples",
    sampleMarkdownHref: "/assets/samples/health-data-sample.md",
    sampleObsidianHref: "/assets/samples/health-data-sample-obsidian.md",
    scheduleDailyTime: "7:00 AM",
    scheduleWeeklyTime: "Monday",
    scheduleWeeklyFile: "Health/<br>Week 32.md",
    scheduleMonthlyTime: "1st of month",
    scheduleMonthlyFile: "Health/<br>August 2026.md",
    scopedRequest: "· scoped request",
    typedQuery: "· typed query",
    codexQuestions: [
      "Compare my average resting heart rate this week with last week.",
      "Show sleep sessions around my running workouts.",
      "Which days are missing sleep data?"
    ],
    claudeQuestions: [
      "Compare my resting heart rate this week with last week.",
      "Show sleep sessions before and after my running workouts.",
      "Find any days with missing sleep data."
    ],
    terminalQuestions: [
      "Compare average resting heart rate for this week and last week.",
      "List sleep sessions around running workouts.",
      "Show dates with missing sleep coverage."
    ]
  };
  var messages = DEFAULT_MESSAGES;
  var messageElement = document.getElementById("healthmd-landing-messages");
  if (messageElement) {
    try {
      messages = Object.assign({}, DEFAULT_MESSAGES, JSON.parse(messageElement.textContent || "{}"));
    } catch (_error) {
      messages = DEFAULT_MESSAGES;
    }
  }

  function escapeHtml(value) {
    return String(value)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/\"/g, "&quot;")
      .replace(/'/g, "&#39;");
  }

  function formatSampleDate() {
    return new Intl.DateTimeFormat(messages.intlLocale, {
      timeZone: "UTC",
      year: "numeric",
      month: "long",
      day: "numeric"
    }).format(new Date(Date.UTC(2026, 7, 2)));
  }

  function formatNumber(value) {
    return new Intl.NumberFormat(messages.intlLocale).format(value);
  }

  function localizedMarkdownSample() {
    return '<h3># ' + escapeHtml(messages.sampleTitle) + '</h3>' +
      '<p><em>*' + escapeHtml(messages.sampleDisclaimer) + '*</em></p>' +
      '<table><thead><tr><th>' + escapeHtml(messages.metric) + '</th><th>' + escapeHtml(messages.value) + '</th></tr></thead><tbody>' +
      '<tr><td>' + escapeHtml(messages.date) + '</td><td>' + escapeHtml(formatSampleDate()) + '</td></tr>' +
      '<tr><td>' + escapeHtml(messages.steps) + '</td><td>' + escapeHtml(formatNumber(8421) + ' ' + messages.stepsUnit) + '</td></tr>' +
      '<tr><td>' + escapeHtml(messages.sleep) + '</td><td>7 ' + escapeHtml(messages.hourShort) + ' 42 ' + escapeHtml(messages.minuteShort) + '</td></tr>' +
      '<tr><td>' + escapeHtml(messages.restingHeartRate) + '</td><td>58 ' + escapeHtml(messages.heartRateUnit) + '</td></tr>' +
      '<tr><td>' + escapeHtml(messages.walkingDistance) + '</td><td>' + escapeHtml(formatNumber(4.1)) + ' mi</td></tr>' +
      '</tbody></table>';
  }

  function localizedObsidianSample() {
    return "---\ndate: 2026-08-02\ntype: health-data\ntags:\n  - health/summary\n---\n\n# " + messages.sampleTitle +
      "\n\n- " + messages.steps + ": " + formatNumber(8421) +
      "\n- " + messages.sleep + ": 7 " + messages.hourShort + " 42 " + messages.minuteShort +
      "\n- " + messages.restingHeartRate + ": 58 " + messages.heartRateUnit +
      "\n- " + messages.walkingDistance + ": " + formatNumber(4.1) + " mi\n\n" + messages.related + ": [[" + messages.healthDashboard + "]]";
  }

  function seededValue(index, salt) {
    var value = Math.sin(index * 91.317 + salt * 47.733) * 43758.5453;
    return value - Math.floor(value);
  }

  function createSvgElement(name) {
    return document.createElementNS(SVG_NAMESPACE, name);
  }

  function setupThreadField() {
    var field = document.querySelector("[data-thread-field]");
    var particles = document.querySelector("[data-thread-particles]");
    if (!field || !particles) return;

    var threadCount = 78;
    var particleCount = 46;

    for (var index = 0; index < threadCount; index += 1) {
      var progress = index / (threadCount - 1);
      var startY = -8 + progress * 392 + (seededValue(index, 1) - 0.5) * 13;
      var centerY = 218;
      var deltaY = startY - centerY;
      var phase = index * 0.67;
      var firstControlX = 155 + seededValue(index, 2) * 38;
      var firstControlY = centerY + deltaY * 1.02 + Math.sin(phase) * 18;
      var secondControlX = 278 + seededValue(index, 3) * 38;
      var secondControlY = centerY + deltaY * 0.96 + Math.sin(phase + 1.2) * 30;
      var firstAnchorX = 365 + seededValue(index, 4) * 32;
      var firstAnchorY = centerY + deltaY * 0.84 + Math.sin(phase + 2.15) * 24;
      var thirdControlX = 430 + seededValue(index, 5) * 32;
      var thirdControlY = centerY + deltaY * 0.73 + Math.sin(phase + 2.8) * 22;
      var fourthControlX = 510 + seededValue(index, 6) * 32;
      var fourthControlY = centerY + deltaY * 0.55 + Math.sin(phase + 3.5) * 18;
      var secondAnchorX = 570 + seededValue(index, 7) * 24;
      var secondAnchorY = centerY + deltaY * 0.4 + Math.sin(phase + 4.05) * 14;
      var fifthControlX = 620 + seededValue(index, 8) * 20;
      var fifthControlY = centerY + deltaY * 0.27 + Math.sin(phase + 4.5) * 10;
      var sixthControlX = 662 + seededValue(index, 9) * 16;
      var sixthControlY = centerY + deltaY * 0.1 + Math.sin(phase + 5.1) * 6;
      var endX = 689 + seededValue(index, 10) * 7;
      var endY = centerY + (seededValue(index, 11) - 0.5) * 12;
      var opacity = 0.17 + seededValue(index, 12) * 0.3;
      var restingOpacity = (opacity + Math.max(0.09, opacity * 0.7)) / 2;
      var path = createSvgElement("path");

      path.setAttribute(
        "d",
        "M -50 " + startY.toFixed(2) +
        " C " + firstControlX.toFixed(2) + " " + firstControlY.toFixed(2) +
        ", " + secondControlX.toFixed(2) + " " + secondControlY.toFixed(2) +
        ", " + firstAnchorX.toFixed(2) + " " + firstAnchorY.toFixed(2) +
        " C " + thirdControlX.toFixed(2) + " " + thirdControlY.toFixed(2) +
        ", " + fourthControlX.toFixed(2) + " " + fourthControlY.toFixed(2) +
        ", " + secondAnchorX.toFixed(2) + " " + secondAnchorY.toFixed(2) +
        " C " + fifthControlX.toFixed(2) + " " + fifthControlY.toFixed(2) +
        ", " + sixthControlX.toFixed(2) + " " + sixthControlY.toFixed(2) +
        ", " + endX.toFixed(2) + " " + endY.toFixed(2)
      );
      path.setAttribute("stroke-width", (0.44 + seededValue(index, 13) * 0.76).toFixed(2));
      path.style.setProperty("--thread-opacity", restingOpacity.toFixed(3));
      field.appendChild(path);
    }

    for (var particleIndex = 0; particleIndex < particleCount; particleIndex += 1) {
      var particleProgress = seededValue(particleIndex, 20);
      var centerBias = Math.pow(particleProgress, 0.84);
      var particleX = -40 + centerBias * 705;
      var spread = 190 * (1 - centerBias) + 13;
      var particleY = 218 + (seededValue(particleIndex, 21) - 0.5) * spread * 2;
      var particleOpacity = 0.12 + seededValue(particleIndex, 22) * 0.3;
      var particleRestingOpacity = (particleOpacity + Math.max(0.08, particleOpacity * 0.58)) / 2;
      var circle = createSvgElement("circle");

      circle.setAttribute("cx", particleX.toFixed(2));
      circle.setAttribute("cy", particleY.toFixed(2));
      circle.setAttribute("r", (0.75 + seededValue(particleIndex, 23) * 1.25).toFixed(2));
      circle.style.setProperty("--particle-opacity", particleRestingOpacity.toFixed(3));
      particles.appendChild(circle);
    }
  }

  function setupReveal() {
    var elements = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
    if (!elements.length) return;

    if (reducedMotion) {
      elements.forEach(function (element) {
        element.classList.add("is-visible");
      });
      return;
    }

    var heroElements = elements.filter(function (element) {
      return element.closest(".hero");
    });
    var deferredElements = elements.filter(function (element) {
      return !element.closest(".hero");
    });

    window.requestAnimationFrame(function () {
      heroElements.forEach(function (element, index) {
        element.style.transitionDelay = index * 90 + "ms";
        element.classList.add("is-visible");
      });
    });

    if (!("IntersectionObserver" in window)) {
      deferredElements.forEach(function (element) {
        element.classList.add("is-visible");
      });
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { threshold: 0.16 });

    deferredElements.forEach(function (element, index) {
      element.style.transitionDelay = (index % 4) * 80 + "ms";
      observer.observe(element);
    });
  }

  function setupExportFormats() {
    var buttons = Array.prototype.slice.call(document.querySelectorAll("[data-export-format]"));
    var stack = document.querySelector("[data-preview-stack]");
    var download = document.querySelector("[data-sample-download]");
    var downloadLabel = download && download.querySelector("span");
    if (!buttons.length || !stack || !download || !downloadLabel) return;

    var samples = {
      markdown: {
        filename: "health-data-sample.md",
        size: "1.2 KB",
        href: messages.sampleMarkdownHref,
        html: localizedMarkdownSample()
      },
      json: {
        filename: "health-data-sample.json",
        size: "328 B",
        href: "/assets/samples/health-data-sample.json",
        text: '{\n  "date": "2026-08-02",\n  "steps": 8421,\n  "sleepMinutes": 462,\n  "restingHeartRateBpm": 58,\n  "walkingDistanceMiles": 4.1\n}'
      },
      csv: {
        filename: "health-data-sample.csv",
        size: "157 B",
        href: "/assets/samples/health-data-sample.csv",
        text: "metric,value,unit\ndate,2026-08-02,\nsteps,8421,steps\nsleep,462,minutes\nresting_heart_rate,58,bpm\nwalking_distance,4.1,mi"
      },
      obsidian: {
        filename: "health-data-sample-obsidian.md",
        size: "1.4 KB",
        href: messages.sampleObsidianHref,
        text: localizedObsidianSample()
      }
    };

    var selectedFormats = buttons.filter(function (button) {
      return button.getAttribute("aria-pressed") === "true";
    }).map(function (button) {
      return button.getAttribute("data-export-format");
    });

    function createPreviewCard(format, index, total, isNew) {
      var sample = samples[format];
      var card = document.createElement("article");
      var header = document.createElement("header");
      var metadata = document.createElement("span");
      var filename = document.createElement("strong");
      var size = document.createElement("small");
      var success = createSvgElement("svg");
      var circle = createSvgElement("circle");
      var check = createSvgElement("path");
      var body = document.createElement("div");
      var depth = total - index - 1;

      card.className = "file-preview" + (isNew ? " is-new" : "");
      card.setAttribute("data-preview-format", format);
      card.style.setProperty("--stack-depth", depth);
      card.style.setProperty(
        "--stack-rotation",
        total > 1 ? ((index % 2 === 0 ? -1 : 1) * (1 + depth * 0.65)) + "deg" : "0deg"
      );
      card.style.zIndex = index + 1;

      header.className = "file-preview-header";
      filename.textContent = sample.filename;
      size.textContent = sample.size;
      metadata.appendChild(filename);
      metadata.appendChild(size);

      success.classList.add("file-success");
      success.setAttribute("viewBox", "0 0 24 24");
      success.setAttribute("aria-label", messages.sampleReady);
      circle.setAttribute("cx", "12");
      circle.setAttribute("cy", "12");
      circle.setAttribute("r", "9");
      check.setAttribute("d", "m8 12 3 3 5-6");
      success.appendChild(circle);
      success.appendChild(check);
      header.appendChild(metadata);
      header.appendChild(success);

      body.className = "file-preview-body";
      if (sample.html) {
        body.innerHTML = sample.html;
      } else {
        var pre = document.createElement("pre");
        pre.textContent = sample.text;
        body.appendChild(pre);
      }

      card.appendChild(header);
      card.appendChild(body);
      return card;
    }

    function renderPreviews(newFormat) {
      stack.replaceChildren();

      if (!selectedFormats.length) {
        var empty = document.createElement("p");
        empty.className = "file-preview-empty";
        empty.textContent = messages.emptyFormats;
        stack.appendChild(empty);
        download.removeAttribute("href");
        download.setAttribute("aria-disabled", "true");
        downloadLabel.textContent = messages.downloadNone;
        return;
      }

      selectedFormats.forEach(function (format, index) {
        stack.appendChild(createPreviewCard(
          format,
          index,
          selectedFormats.length,
          format === newFormat
        ));
      });

      download.setAttribute("href", samples[selectedFormats[selectedFormats.length - 1]].href);
      download.removeAttribute("aria-disabled");
      downloadLabel.textContent = selectedFormats.length === 1
        ? messages.downloadOne
        : messages.downloadMany.replace("{count}", String(selectedFormats.length));
    }

    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        var format = button.getAttribute("data-export-format");
        var selectedIndex = selectedFormats.indexOf(format);
        var isSelecting = selectedIndex === -1;
        if (!samples[format]) return;

        if (isSelecting) {
          selectedFormats.push(format);
        } else {
          selectedFormats.splice(selectedIndex, 1);
        }

        button.classList.toggle("is-active", isSelecting);
        button.setAttribute("aria-pressed", isSelecting ? "true" : "false");
        renderPreviews(isSelecting ? format : null);
      });
    });

    download.addEventListener("click", function (event) {
      if (!selectedFormats.length) {
        event.preventDefault();
        return;
      }
      if (selectedFormats.length === 1) return;

      event.preventDefault();
      selectedFormats.forEach(function (format) {
        var link = document.createElement("a");
        link.href = samples[format].href;
        link.download = samples[format].filename;
        link.click();
      });
    });

    renderPreviews(null);
  }

  function setupSchedulePreview() {
    var buttons = Array.prototype.slice.call(document.querySelectorAll("[data-schedule-frequency]"));
    var time = document.querySelector("[data-schedule-time]");
    var file = document.querySelector("[data-schedule-file]");
    if (!buttons.length || !time || !file) return;

    var schedules = {
      daily: { time: messages.scheduleDailyTime, file: "Health/<br>2026-08-03.md" },
      weekly: { time: messages.scheduleWeeklyTime, file: messages.scheduleWeeklyFile },
      monthly: { time: messages.scheduleMonthlyTime, file: messages.scheduleMonthlyFile }
    };

    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        var frequency = button.getAttribute("data-schedule-frequency");
        var schedule = schedules[frequency];
        if (!schedule) return;

        buttons.forEach(function (option) {
          var active = option === button;
          option.classList.toggle("is-active", active);
          option.setAttribute("aria-pressed", active ? "true" : "false");
        });

        time.textContent = schedule.time;
        file.innerHTML = schedule.file;
      });
    });
  }

  function setupAgentPreview() {
    var preview = document.querySelector("[data-agent-preview]");
    if (!preview) return;

    var buttons = Array.prototype.slice.call(preview.querySelectorAll("[data-agent-client]"));
    var questions = Array.prototype.slice.call(preview.querySelectorAll("[data-agent-question]"));
    var transportTitle = preview.querySelector("[data-agent-transport-title]");
    var transportNote = preview.querySelector("[data-agent-transport-note]");
    if (!buttons.length || questions.length !== 3 || !transportTitle || !transportNote) return;

    var clients = {
      codex: {
        title: "Health.md MCP",
        note: messages.scopedRequest,
        questions: messages.codexQuestions
      },
      claude: {
        title: "Health.md MCP",
        note: messages.scopedRequest,
        questions: messages.claudeQuestions
      },
      terminal: {
        title: "Health.md CLI",
        note: messages.typedQuery,
        questions: messages.terminalQuestions
      }
    };

    function selectClient(clientName) {
      var client = clients[clientName];
      if (!client) return;

      buttons.forEach(function (button) {
        var active = button.getAttribute("data-agent-client") === clientName;
        button.classList.toggle("is-active", active);
        button.setAttribute("aria-pressed", active ? "true" : "false");
      });

      questions.forEach(function (question, index) {
        question.textContent = client.questions[index];
      });
      transportTitle.textContent = client.title;
      transportNote.textContent = client.note;
    }

    buttons.forEach(function (button) {
      button.addEventListener("click", function () {
        selectClient(button.getAttribute("data-agent-client"));
      });
    });
  }

  setupThreadField();
  setupReveal();
  setupExportFormats();
  setupSchedulePreview();
  setupAgentPreview();
})();

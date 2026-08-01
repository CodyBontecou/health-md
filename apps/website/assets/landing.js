(function () {
  "use strict";

  document.documentElement.classList.add("has-js");

  var reducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function setupHeader() {
    var header = document.querySelector("[data-site-header]");
    var toggle = document.querySelector("[data-menu-toggle]");
    var nav = document.querySelector("[data-primary-nav]");

    function syncHeader() {
      if (header) header.classList.toggle("is-scrolled", window.scrollY > 8);
    }

    function closeMenu() {
      if (!toggle || !nav) return;
      toggle.setAttribute("aria-expanded", "false");
      nav.classList.remove("is-open");
      document.body.classList.remove("menu-open");
    }

    syncHeader();
    window.addEventListener("scroll", syncHeader, { passive: true });

    if (!toggle || !nav) return;

    toggle.addEventListener("click", function () {
      var willOpen = toggle.getAttribute("aria-expanded") !== "true";
      toggle.setAttribute("aria-expanded", willOpen ? "true" : "false");
      nav.classList.toggle("is-open", willOpen);
      document.body.classList.toggle("menu-open", willOpen);
    });

    nav.addEventListener("click", function (event) {
      if (event.target.closest("a")) closeMenu();
    });

    document.addEventListener("keydown", function (event) {
      if (event.key === "Escape") {
        closeMenu();
        toggle.focus();
      }
    });

    window.addEventListener("resize", function () {
      if (window.innerWidth > 1200) closeMenu();
    });
  }

  function setupReveal() {
    var elements = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
    if (!elements.length) return;

    if (reducedMotion || !("IntersectionObserver" in window)) {
      elements.forEach(function (element) { element.classList.add("is-visible"); });
      return;
    }

    var observer = new IntersectionObserver(function (entries) {
      entries.forEach(function (entry) {
        if (!entry.isIntersecting) return;
        entry.target.classList.add("is-visible");
        observer.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -8%", threshold: 0.08 });

    elements.forEach(function (element, index) {
      element.style.transitionDelay = Math.min(index % 4, 3) * 55 + "ms";
      observer.observe(element);
    });
  }

  function setupFormatTabs() {
    var root = document.querySelector("[data-format-tabs]");
    if (!root) return;

    var tabs = Array.prototype.slice.call(root.querySelectorAll("[data-format-tab]"));
    var panels = Array.prototype.slice.call(document.querySelectorAll("[data-format-panel]"));
    var filename = document.querySelector("[data-format-filename]");
    var filenames = {
      markdown: "Health/2026/08/2026-08-01.md",
      json: "Health/2026/08/2026-08-01.json",
      csv: "Health/2026/08/2026-08-01.csv"
    };

    function selectTab(tab, moveFocus) {
      var selected = tab.getAttribute("data-format-tab");

      tabs.forEach(function (item) {
        var active = item === tab;
        item.setAttribute("aria-selected", active ? "true" : "false");
        item.tabIndex = active ? 0 : -1;
      });

      panels.forEach(function (panel) {
        panel.hidden = panel.getAttribute("data-format-panel") !== selected;
      });

      if (filename && filenames[selected]) filename.textContent = filenames[selected];
      if (moveFocus) tab.focus();
    }

    tabs.forEach(function (tab, index) {
      tab.addEventListener("click", function () { selectTab(tab, false); });
      tab.addEventListener("keydown", function (event) {
        var nextIndex = null;
        if (event.key === "ArrowRight") nextIndex = (index + 1) % tabs.length;
        if (event.key === "ArrowLeft") nextIndex = (index - 1 + tabs.length) % tabs.length;
        if (event.key === "Home") nextIndex = 0;
        if (event.key === "End") nextIndex = tabs.length - 1;
        if (nextIndex === null) return;
        event.preventDefault();
        selectTab(tabs[nextIndex], true);
      });
    });
  }

  function hexToRgb(hex) {
    var value = hex.replace("#", "");
    if (value.length === 3) value = value.split("").map(function (part) { return part + part; }).join("");
    return {
      r: parseInt(value.slice(0, 2), 16),
      g: parseInt(value.slice(2, 4), 16),
      b: parseInt(value.slice(4, 6), 16)
    };
  }

  function rgba(color, alpha) {
    var rgb = hexToRgb(color);
    return "rgba(" + rgb.r + "," + rgb.g + "," + rgb.b + "," + alpha + ")";
  }

  function Helix(canvas, options) {
    this.canvas = canvas;
    this.options = options || {};
    this.context = canvas.getContext("2d");
    this.width = 0;
    this.height = 0;
    this.dpr = 1;
    this.frameId = null;
    this.active = false;
    this.pointerTarget = 0;
    this.pointerOffset = 0;
    this.boundDraw = this.animate.bind(this);
    this.resize = this.resize.bind(this);
    this.observe();
  }

  Helix.prototype.observe = function () {
    var self = this;
    var parent = this.canvas.parentElement;

    this.resize();

    if ("ResizeObserver" in window) {
      this.resizeObserver = new ResizeObserver(function () {
        self.resize();
        if (reducedMotion) self.draw(0);
      });
      this.resizeObserver.observe(parent);
    } else {
      window.addEventListener("resize", this.resize);
    }

    if (parent && !reducedMotion) {
      parent.addEventListener("pointermove", function (event) {
        var bounds = parent.getBoundingClientRect();
        self.pointerTarget = ((event.clientY - bounds.top) / Math.max(bounds.height, 1) - 0.5) * 28;
      }, { passive: true });
      parent.addEventListener("pointerleave", function () { self.pointerTarget = 0; }, { passive: true });
    }

    if (reducedMotion) {
      this.draw(0);
      return;
    }

    if ("IntersectionObserver" in window) {
      this.visibilityObserver = new IntersectionObserver(function (entries) {
        entries.forEach(function (entry) {
          if (entry.target !== self.canvas) return;
          if (entry.isIntersecting) self.start();
          else self.stop();
        });
      }, { rootMargin: "120px" });
      this.visibilityObserver.observe(this.canvas);
    } else {
      this.start();
    }
  };

  Helix.prototype.resize = function () {
    var rect = this.canvas.getBoundingClientRect();
    var width = Math.max(1, Math.round(rect.width));
    var height = Math.max(1, Math.round(rect.height));
    var dpr = Math.min(window.devicePixelRatio || 1, 2);

    if (this.width === width && this.height === height && this.dpr === dpr) return;

    this.width = width;
    this.height = height;
    this.dpr = dpr;
    this.canvas.width = Math.round(width * dpr);
    this.canvas.height = Math.round(height * dpr);
    this.context.setTransform(dpr, 0, 0, dpr, 0, 0);
    this.draw(0);
  };

  Helix.prototype.start = function () {
    if (this.active) return;
    this.active = true;
    this.frameId = window.requestAnimationFrame(this.boundDraw);
  };

  Helix.prototype.stop = function () {
    this.active = false;
    if (this.frameId !== null) window.cancelAnimationFrame(this.frameId);
    this.frameId = null;
  };

  Helix.prototype.animate = function (time) {
    if (!this.active) return;
    if (this.options.full && this.lastRenderTime && time - this.lastRenderTime < 32) {
      this.frameId = window.requestAnimationFrame(this.boundDraw);
      return;
    }
    this.lastRenderTime = time;
    this.draw(time);
    this.frameId = window.requestAnimationFrame(this.boundDraw);
  };

  Helix.prototype.point = function (x, phase, strand) {
    var narrow = this.width < 720;
    var wavelength = Math.max(narrow ? 220 : 350, this.width * (this.options.compact ? 0.26 : 0.31));
    var theta = (x / wavelength) * Math.PI * 2 + phase;
    var amplitude = Math.min(this.height * (narrow ? 0.15 : 0.26), narrow ? 78 : 128);
    var centerRatio = narrow && !this.options.compact ? 0.39 : 0.5;
    var center = this.height * centerRatio + this.pointerOffset;
    var direction = strand === 0 ? 1 : -1;

    return {
      x: x,
      y: center + direction * Math.sin(theta) * amplitude,
      depth: direction * Math.cos(theta),
      theta: theta
    };
  };

  Helix.prototype.fullGeometry = function () {
    var narrow = this.width < 720;
    var radius = narrow
      ? Math.min(this.height * 0.34, 270)
      : Math.min(this.height * 0.36, 365);

    return {
      centerY: this.height * 0.52 + this.pointerOffset,
      radius: radius,
      pitch: radius * 2 * (narrow ? 1.38 : 1.68),
      skew: narrow ? 0.065 : 0.085,
      grooveOffset: Math.PI * 0.86
    };
  };

  Helix.prototype.fullPoint = function (axisX, phase, strand, geometry) {
    var angle = (axisX / geometry.pitch) * Math.PI * 2 + phase;
    if (strand === 1) angle += geometry.grooveOffset;

    var depth = Math.cos(angle);
    var perspective = 1 + depth * 0.035;

    return {
      x: axisX + depth * geometry.radius * geometry.skew,
      y: geometry.centerY + Math.sin(angle) * geometry.radius * perspective,
      depth: depth,
      strand: strand
    };
  };

  Helix.prototype.drawFull = function (time) {
    var ctx = this.context;
    var width = this.width;
    var height = this.height;
    var colorA = this.options.colorA;
    var colorB = this.options.colorB;
    var ink = this.options.ink;
    var phase = time * this.options.speed;
    var narrow = width < 720;
    var geometry = this.fullGeometry();
    var segmentStep = narrow ? 4 : 6;
    var overscan = geometry.radius * geometry.skew + 24;
    var items = [];

    this.pointerOffset += (this.pointerTarget - this.pointerOffset) * 0.035;
    geometry.centerY = height * 0.52 + this.pointerOffset;
    ctx.clearRect(0, 0, width, height);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    for (var strand = 0; strand < 2; strand += 1) {
      for (var axisX = -overscan; axisX <= width + overscan; axisX += segmentStep) {
        var from = this.fullPoint(axisX, phase, strand, geometry);
        var to = this.fullPoint(axisX + segmentStep, phase, strand, geometry);
        items.push({
          kind: "backbone",
          strand: strand,
          from: from,
          to: to,
          depth: (from.depth + to.depth) / 2,
          order: 1
        });
      }
    }

    var rungStep = geometry.pitch / 10.5;
    for (var rungX = -geometry.pitch; rungX <= width + geometry.pitch; rungX += rungStep) {
      var first = this.fullPoint(rungX, phase, 0, geometry);
      var second = this.fullPoint(rungX, phase, 1, geometry);
      var middle = {
        x: (first.x + second.x) / 2,
        y: (first.y + second.y) / 2,
        depth: (first.depth + second.depth) / 2
      };

      items.push({
        kind: "rung",
        strand: 0,
        from: middle,
        to: first,
        depth: (middle.depth + first.depth) / 2,
        order: 0
      });
      items.push({
        kind: "rung",
        strand: 1,
        from: middle,
        to: second,
        depth: (middle.depth + second.depth) / 2,
        order: 0
      });
      items.push({ kind: "node", strand: 0, point: first, depth: first.depth, order: 2 });
      items.push({ kind: "node", strand: 1, point: second, depth: second.depth, order: 2 });
    }

    items.sort(function (left, right) {
      if (left.depth !== right.depth) return left.depth - right.depth;
      return left.order - right.order;
    });

    items.forEach(function (item) {
      var front = (item.depth + 1) / 2;
      var strandColor = item.strand === 0 ? colorA : colorB;

      if (item.kind === "rung") {
        ctx.strokeStyle = rgba(ink, 0.38 + front * 0.32);
        ctx.lineWidth = 0.9 + front * 0.7;
        ctx.beginPath();
        ctx.moveTo(item.from.x, item.from.y);
        ctx.lineTo(item.to.x, item.to.y);
        ctx.stroke();
        return;
      }

      if (item.kind === "node") {
        var radius = 1.8 + front * 1.7;
        ctx.fillStyle = rgba(ink, 0.28 + front * 0.3);
        ctx.beginPath();
        ctx.arc(item.point.x, item.point.y, radius + 0.65, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = rgba(strandColor, 0.72 + front * 0.25);
        ctx.beginPath();
        ctx.arc(item.point.x, item.point.y, radius, 0, Math.PI * 2);
        ctx.fill();
        ctx.fillStyle = rgba("#ffffff", 0.48 + front * 0.35);
        ctx.beginPath();
        ctx.arc(item.point.x - radius * 0.28, item.point.y - radius * 0.3, Math.max(0.5, radius * 0.24), 0, Math.PI * 2);
        ctx.fill();
        return;
      }

      var tubeWidth = 1.9 + front * 3.7;
      ctx.strokeStyle = rgba(ink, 0.2 + front * 0.28);
      ctx.lineWidth = tubeWidth + 1.15;
      ctx.beginPath();
      ctx.moveTo(item.from.x, item.from.y);
      ctx.lineTo(item.to.x, item.to.y);
      ctx.stroke();

      ctx.strokeStyle = rgba(strandColor, 0.58 + front * 0.39);
      ctx.lineWidth = tubeWidth;
      ctx.beginPath();
      ctx.moveTo(item.from.x, item.from.y);
      ctx.lineTo(item.to.x, item.to.y);
      ctx.stroke();

      ctx.strokeStyle = rgba("#ffffff", 0.28 + front * 0.42);
      ctx.lineWidth = Math.max(0.55, tubeWidth * 0.2);
      ctx.beginPath();
      ctx.moveTo(item.from.x - 0.45, item.from.y - 0.55);
      ctx.lineTo(item.to.x - 0.45, item.to.y - 0.55);
      ctx.stroke();
    });
  };

  Helix.prototype.draw = function (time) {
    if (!this.width || !this.height) return;
    if (this.options.full) {
      this.drawFull(time);
      return;
    }

    var ctx = this.context;
    var width = this.width;
    var height = this.height;
    var colorA = this.options.colorA || "#ff4f22";
    var colorB = this.options.colorB || "#7357ff";
    var ink = this.options.ink || "#121212";
    var speed = this.options.speed || 0.00042;
    var phase = time * speed;
    var narrow = width < 720;
    var spacing = narrow ? 46 : 62;
    var step = narrow ? 4 : 3;

    this.pointerOffset += (this.pointerTarget - this.pointerOffset) * 0.045;
    ctx.clearRect(0, 0, width, height);
    ctx.lineCap = "round";
    ctx.lineJoin = "round";

    ctx.save();
    ctx.setLineDash([2, 8]);
    ctx.strokeStyle = rgba(ink, this.options.compact ? 0.1 : 0.14);
    ctx.lineWidth = 1;
    ctx.beginPath();
    var axisRatio = narrow && !this.options.compact ? 0.39 : 0.5;
    ctx.moveTo(0, height * axisRatio);
    ctx.lineTo(width, height * axisRatio);
    ctx.stroke();
    ctx.restore();

    for (var rungX = -spacing; rungX <= width + spacing; rungX += spacing) {
      var a = this.point(rungX, phase, 0);
      var b = this.point(rungX, phase, 1);
      var front = (a.depth + 1) / 2;

      ctx.strokeStyle = rgba(ink, 0.11 + front * 0.18);
      ctx.lineWidth = 0.7 + front * 0.7;
      ctx.beginPath();
      ctx.moveTo(a.x, a.y);
      ctx.lineTo(b.x, b.y);
      ctx.stroke();

      ctx.fillStyle = rgba(ink, 0.28);
      ctx.beginPath();
      ctx.arc((a.x + b.x) / 2, (a.y + b.y) / 2, 1.6, 0, Math.PI * 2);
      ctx.fill();

      [a, b].forEach(function (point, index) {
        var pointColor = index === 0 ? colorA : colorB;
        var radius = 3.1 + ((point.depth + 1) / 2) * 3.7;
        ctx.fillStyle = pointColor;
        ctx.strokeStyle = ink;
        ctx.lineWidth = 1;
        ctx.beginPath();
        ctx.arc(point.x, point.y, radius, 0, Math.PI * 2);
        ctx.fill();
        ctx.stroke();
      });
    }

    function drawStrand(strand, color, helix) {
      for (var x = -step; x <= width + step; x += step) {
        var from = helix.point(x - step, phase, strand);
        var to = helix.point(x, phase, strand);
        var depth = (from.depth + to.depth + 2) / 4;
        ctx.strokeStyle = rgba(color, 0.38 + depth * 0.62);
        ctx.lineWidth = 1.4 + depth * (narrow ? 3.2 : 4.8);
        ctx.beginPath();
        ctx.moveTo(from.x, from.y);
        ctx.lineTo(to.x, to.y);
        ctx.stroke();
      }
    }

    drawStrand(1, colorB, this);
    drawStrand(0, colorA, this);

    var pulseCount = 4;
    var pulseSize = 10;
    for (var pulseIndex = 0; pulseIndex < pulseCount; pulseIndex += 1) {
      var travel = ((time * 0.045 + pulseIndex * (width + 180) / pulseCount) % (width + 180)) - 90;
      var strand = pulseIndex % 2;
      var pulse = this.point(travel, phase, strand);
      var pulseColor = strand === 0 ? colorA : colorB;
      ctx.fillStyle = ink;
      ctx.fillRect(pulse.x - pulseSize / 2, pulse.y - pulseSize / 2, pulseSize, pulseSize);
      ctx.fillStyle = pulseColor;
      ctx.fillRect(pulse.x - 1.5, pulse.y - 1.5, 3, 3);
    }
  };

  function setupHelices() {
    var mainCanvas = document.querySelector("[data-strand-canvas]");
    var downloadCanvas = document.querySelector("[data-download-strand]");

    function startMainFallback() {
      if (!mainCanvas || mainCanvas.__healthMdCanvasFallback || mainCanvas.dataset.renderer === "three") return;

      if (!mainCanvas.getContext("2d")) {
        var replacement = mainCanvas.cloneNode(false);
        mainCanvas.replaceWith(replacement);
        mainCanvas = replacement;
      }

      mainCanvas.__healthMdCanvasFallback = true;
      mainCanvas.dataset.renderer = "canvas";
      new Helix(mainCanvas, {
        speed: 0.0002,
        full: true,
        colorA: "#d4d4d0",
        colorB: "#e1e1de",
        ink: "#d0d0cc"
      });
    }

    if (mainCanvas && mainCanvas.hasAttribute("data-three-strand")) {
      mainCanvas.addEventListener("healthmd-three-failed", startMainFallback, { once: true });
      window.setTimeout(function () {
        if (mainCanvas.dataset.renderer !== "three") startMainFallback();
      }, 3000);
    } else {
      startMainFallback();
    }

    if (downloadCanvas) new Helix(downloadCanvas, {
      speed: -0.00024,
      compact: true,
      colorA: "#ff4f22",
      colorB: "#7357ff"
    });
  }

  function setupPageVisibility() {
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) window.dispatchEvent(new Event("resize"));
    });
  }

  setupHeader();
  setupReveal();
  setupFormatTabs();
  setupHelices();
  setupPageVisibility();
})();

(function () {
  "use strict";

  document.documentElement.classList.add("has-js");

  var reducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  function setupReveal() {
    var elements = Array.prototype.slice.call(document.querySelectorAll(".reveal"));
    if (!elements.length) return;

    if (reducedMotion) {
      elements.forEach(function (element) { element.classList.add("is-visible"); });
      return;
    }

    window.requestAnimationFrame(function () {
      elements.forEach(function (element, index) {
        element.style.transitionDelay = index * 70 + "ms";
        element.classList.add("is-visible");
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
    this.lastRenderTime = 0;
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
      this.resizeObserver.observe(parent || this.canvas);
    } else {
      window.addEventListener("resize", this.resize);
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

    if (!this.lastRenderTime || time - this.lastRenderTime >= 32) {
      this.lastRenderTime = time;
      this.draw(time);
    }

    this.frameId = window.requestAnimationFrame(this.boundDraw);
  };

  Helix.prototype.fullGeometry = function () {
    var narrow = this.width < 720;
    var radius = narrow
      ? Math.min(this.height * 0.34, 270)
      : Math.min(this.height * 0.36, 365);

    return {
      centerY: this.height * 0.52,
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

  Helix.prototype.draw = function (time) {
    if (!this.width || !this.height) return;

    var ctx = this.context;
    var width = this.width;
    var colorA = this.options.colorA;
    var colorB = this.options.colorB;
    var ink = this.options.ink;
    var phase = time * this.options.speed;
    var narrow = width < 720;
    var geometry = this.fullGeometry();
    var segmentStep = narrow ? 4 : 6;
    var overscan = geometry.radius * geometry.skew + 24;
    var items = [];

    ctx.clearRect(0, 0, this.width, this.height);
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

      items.push({ kind: "rung", strand: 0, from: middle, to: first, depth: (middle.depth + first.depth) / 2, order: 0 });
      items.push({ kind: "rung", strand: 1, from: middle, to: second, depth: (middle.depth + second.depth) / 2, order: 0 });
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
        ctx.strokeStyle = rgba(ink, 0.24 + front * 0.22);
        ctx.lineWidth = 0.7 + front * 0.55;
        ctx.beginPath();
        ctx.moveTo(item.from.x, item.from.y);
        ctx.lineTo(item.to.x, item.to.y);
        ctx.stroke();
        return;
      }

      if (item.kind === "node") {
        var radius = 1.8 + front * 1.7;
        ctx.fillStyle = rgba(ink, 0.2 + front * 0.22);
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
      ctx.strokeStyle = rgba(ink, 0.14 + front * 0.2);
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

  function setupHeroFallback() {
    var canvas = document.querySelector("[data-strand-canvas]");
    if (!canvas) return;

    function startFallback() {
      if (!canvas || canvas.__healthMdCanvasFallback || canvas.dataset.renderer === "three") return;

      if (!canvas.getContext("2d")) {
        var replacement = canvas.cloneNode(false);
        canvas.replaceWith(replacement);
        canvas = replacement;
      }

      canvas.__healthMdCanvasFallback = true;
      canvas.dataset.renderer = "canvas";
      new Helix(canvas, {
        speed: 0.00017,
        colorA: "#dcdcd8",
        colorB: "#e8e8e5",
        ink: "#dadad6"
      });
    }

    if (canvas.hasAttribute("data-three-strand")) {
      canvas.addEventListener("healthmd-three-failed", startFallback, { once: true });
      window.setTimeout(function () {
        if (canvas.dataset.renderer !== "three") startFallback();
      }, 3000);
    } else {
      startFallback();
    }
  }

  function setupPageVisibility() {
    document.addEventListener("visibilitychange", function () {
      if (!document.hidden) window.dispatchEvent(new Event("resize"));
    });
  }

  setupReveal();
  setupHeroFallback();
  setupPageVisibility();
})();

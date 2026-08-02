(function () {
  "use strict";

  document.documentElement.classList.add("has-js");

  var reducedMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  var SVG_NAMESPACE = "http://www.w3.org/2000/svg";

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

    window.requestAnimationFrame(function () {
      elements.forEach(function (element, index) {
        element.style.transitionDelay = index * 90 + "ms";
        element.classList.add("is-visible");
      });
    });
  }

  setupThreadField();
  setupReveal();
})();

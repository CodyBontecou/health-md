import * as THREE from "./vendor/three.module.min.js";

const canvas = document.querySelector("[data-three-strand]");

if (canvas && canvas.dataset.renderer !== "canvas") {
  canvas.dataset.renderer = "three-loading";

  try {
    const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(20, 1, 0.1, 100);
    const renderer = new THREE.WebGLRenderer({
      canvas,
      alpha: true,
      antialias: true,
      powerPreference: "high-performance",
      premultipliedAlpha: true,
    });

    renderer.setClearColor(0x000000, 0);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
    renderer.outputColorSpace = THREE.SRGBColorSpace;
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.04;

    camera.position.set(0, 0, 30);
    camera.lookAt(0, 0, 0);

    scene.fog = new THREE.Fog(0xf6f6f2, 24, 39);
    scene.add(new THREE.HemisphereLight(0xffffff, 0xe5e5df, 1.8));

    const keyLight = new THREE.DirectionalLight(0xffffff, 2.45);
    keyLight.position.set(-5, 7, 11);
    scene.add(keyLight);

    const fillLight = new THREE.DirectionalLight(0xf8f8f5, 0.55);
    fillLight.position.set(-9, -6, 4);
    scene.add(fillLight);

    const rimLight = new THREE.DirectionalLight(0xffffff, 0.9);
    rimLight.position.set(8, -4, 6);
    scene.add(rimLight);

    let helix = null;
    let frameId = null;
    let active = false;
    let lastFrame = 0;
    let rotation = 0.42;
    let pointerX = 0;
    let pointerY = 0;
    let targetPointerX = 0;
    let targetPointerY = 0;

    function physicalMaterial(color, roughness, clearcoat = 0.12) {
      return new THREE.MeshPhysicalMaterial({
        color,
        roughness,
        metalness: 0,
        clearcoat,
        clearcoatRoughness: 0.72,
      });
    }

    const backboneMaterials = [
      physicalMaterial(0xd6d6d2, 0.38, 0.28),
      physicalMaterial(0xe1e1dd, 0.43, 0.22),
    ];

    const baseMaterials = [
      physicalMaterial(0xdfdfdb, 0.56, 0.08),
      physicalMaterial(0xe9e9e5, 0.6, 0.06),
      physicalMaterial(0xdbdbd7, 0.54, 0.1),
      physicalMaterial(0xe5e5e1, 0.58, 0.08),
    ];

    const jointMaterials = [
      physicalMaterial(0xd2d2ce, 0.4, 0.24),
      physicalMaterial(0xddddda, 0.44, 0.2),
    ];

    const hydrogenMaterial = physicalMaterial(0xccccca, 0.66, 0);
    const pairSequence = [
      [0, 1, 2],
      [2, 3, 3],
      [1, 0, 2],
      [3, 2, 3],
      [2, 3, 3],
      [0, 1, 2],
      [3, 2, 3],
      [1, 0, 2],
    ];

    function helixPoint(axisX, pitch, radius, strand) {
      let angle = (axisX / pitch) * Math.PI * 2;
      if (strand === 1) angle += Math.PI * 0.86;
      return new THREE.Vector3(
        axisX,
        Math.sin(angle) * radius,
        Math.cos(angle) * radius,
      );
    }

    function disposeObject(object) {
      object.traverse((child) => {
        child.geometry?.dispose();
      });
      object.parent?.remove(object);
    }

    function addRod(group, from, to, material, radius, radialSegments = 8) {
      const midpoint = new THREE.Vector3().addVectors(from, to).multiplyScalar(0.5);
      const direction = new THREE.Vector3().subVectors(to, from);
      const length = direction.length();
      const geometry = new THREE.CylinderGeometry(radius, radius, length, radialSegments, 1, false);
      const rod = new THREE.Mesh(geometry, material);
      rod.position.copy(midpoint);
      rod.quaternion.setFromUnitVectors(
        new THREE.Vector3(0, 1, 0),
        direction.normalize(),
      );
      group.add(rod);
    }

    function buildHelix(width, height) {
      if (helix) disposeObject(helix);

      const aspect = width / Math.max(height, 1);
      const narrow = aspect < 0.75;
      const worldHeight = 10;
      const worldWidth = worldHeight * aspect;
      const radius = narrow ? 3.15 : 3.62;
      const pitch = radius * 2 * (narrow ? 1.3 : 1.68);
      const axisLength = worldWidth + pitch * 0.58;
      const tubeRadius = narrow ? 0.034 : 0.039;
      const baseRadius = narrow ? 0.016 : 0.019;
      const hydrogenRadius = narrow ? 0.0032 : 0.0038;
      const group = new THREE.Group();
      const curvePoints = narrow ? 180 : 260;

      for (let strand = 0; strand < 2; strand += 1) {
        const points = [];
        for (let index = 0; index <= curvePoints; index += 1) {
          const axisX = -axisLength / 2 + (index / curvePoints) * axisLength;
          points.push(helixPoint(axisX, pitch, radius, strand));
        }

        const curve = new THREE.CatmullRomCurve3(points, false, "centripetal");
        const geometry = new THREE.TubeGeometry(
          curve,
          curvePoints,
          tubeRadius,
          10,
          false,
        );
        group.add(new THREE.Mesh(geometry, backboneMaterials[strand]));
      }

      const rungStep = pitch / 10.5;
      const backboneJointGeometry = new THREE.SphereGeometry(tubeRadius * 1.48, 12, 9);
      const baseCapGeometry = new THREE.SphereGeometry(baseRadius * 1.04, 9, 7);
      let pairIndex = 0;

      for (let axisX = -axisLength / 2; axisX <= axisLength / 2; axisX += rungStep) {
        const first = helixPoint(axisX, pitch, radius, 0);
        const second = helixPoint(axisX, pitch, radius, 1);
        const connector = new THREE.Vector3().subVectors(second, first);
        const innerFirst = first.clone().addScaledVector(connector, 0.465);
        const innerSecond = first.clone().addScaledVector(connector, 0.535);
        const pair = pairSequence[pairIndex % pairSequence.length];
        const firstBaseMaterial = baseMaterials[pair[0]];
        const secondBaseMaterial = baseMaterials[pair[1]];
        const bondCount = pair[2];

        addRod(group, first, innerFirst, firstBaseMaterial, baseRadius, 10);
        addRod(group, innerSecond, second, secondBaseMaterial, baseRadius, 10);

        const bondOffset = new THREE.Vector3(0, -connector.z, connector.y).normalize();
        for (let bondIndex = 0; bondIndex < bondCount; bondIndex += 1) {
          const offset = (bondIndex - (bondCount - 1) / 2) * baseRadius * 1.55;
          const bondFrom = innerFirst.clone().addScaledVector(bondOffset, offset);
          const bondTo = innerSecond.clone().addScaledVector(bondOffset, offset);
          addRod(group, bondFrom, bondTo, hydrogenMaterial, hydrogenRadius, 6);
        }

        const firstBaseCap = new THREE.Mesh(baseCapGeometry, firstBaseMaterial);
        firstBaseCap.position.copy(innerFirst);
        group.add(firstBaseCap);

        const secondBaseCap = new THREE.Mesh(baseCapGeometry, secondBaseMaterial);
        secondBaseCap.position.copy(innerSecond);
        group.add(secondBaseCap);

        const firstJoint = new THREE.Mesh(backboneJointGeometry, jointMaterials[0]);
        firstJoint.position.copy(first);
        group.add(firstJoint);

        const secondJoint = new THREE.Mesh(backboneJointGeometry, jointMaterials[1]);
        secondJoint.position.copy(second);
        group.add(secondJoint);

        pairIndex += 1;
      }

      group.rotation.x = rotation;
      group.rotation.y = pointerX;
      group.rotation.z = pointerY;
      scene.add(group);
      helix = group;

      camera.aspect = aspect;
      camera.updateProjectionMatrix();
    }

    function resize() {
      const bounds = canvas.getBoundingClientRect();
      const width = Math.max(1, Math.round(bounds.width));
      const height = Math.max(1, Math.round(bounds.height));
      renderer.setPixelRatio(Math.min(window.devicePixelRatio || 1, 1.75));
      renderer.setSize(width, height, false);
      buildHelix(width, height);
      renderer.render(scene, camera);
    }

    function render(time) {
      if (!active || !helix) return;

      if (time - lastFrame >= 32) {
        lastFrame = time;
        rotation = time * 0.00017 + 0.42;
        pointerX += (targetPointerX - pointerX) * 0.035;
        pointerY += (targetPointerY - pointerY) * 0.035;
        helix.rotation.x = rotation;
        helix.rotation.y = pointerX;
        helix.rotation.z = pointerY;
        renderer.render(scene, camera);
      }

      frameId = window.requestAnimationFrame(render);
    }

    function start() {
      if (active || reducedMotion) return;
      active = true;
      frameId = window.requestAnimationFrame(render);
    }

    function stop() {
      active = false;
      if (frameId !== null) window.cancelAnimationFrame(frameId);
      frameId = null;
    }

    const stage = canvas.parentElement;
    stage?.addEventListener("pointermove", (event) => {
      const bounds = stage.getBoundingClientRect();
      const normalizedX = (event.clientX - bounds.left) / Math.max(bounds.width, 1) - 0.5;
      const normalizedY = (event.clientY - bounds.top) / Math.max(bounds.height, 1) - 0.5;
      targetPointerX = normalizedX * 0.055;
      targetPointerY = normalizedY * -0.018;
    }, { passive: true });

    stage?.addEventListener("pointerleave", () => {
      targetPointerX = 0;
      targetPointerY = 0;
    }, { passive: true });

    const resizeObserver = new ResizeObserver(resize);
    resizeObserver.observe(stage || canvas);

    if ("IntersectionObserver" in window) {
      const visibilityObserver = new IntersectionObserver((entries) => {
        for (const entry of entries) {
          if (entry.isIntersecting) start();
          else stop();
        }
      }, { rootMargin: "120px" });
      visibilityObserver.observe(canvas);
    } else {
      start();
    }

    resize();
    canvas.dataset.renderer = "three";
    canvas.dispatchEvent(new CustomEvent("healthmd-three-ready"));
  } catch (error) {
    delete canvas.dataset.renderer;
    canvas.dispatchEvent(new CustomEvent("healthmd-three-failed"));
    console.warn("Three.js hero renderer unavailable; using Canvas fallback.", error);
  }
}

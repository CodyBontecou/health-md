import * as THREE from "./vendor/three.module.min.js";

const canvas = document.querySelector("[data-three-strand]");

if (canvas && canvas.dataset.renderer !== "canvas") {
  canvas.dataset.renderer = "three-loading";

  try {
    const reducedMotion = window.matchMedia?.("(prefers-reduced-motion: reduce)").matches ?? false;
    const scene = new THREE.Scene();
    const camera = new THREE.OrthographicCamera(-5, 5, 5, -5, 0.1, 100);
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

    camera.position.set(0, 0, 24);
    camera.lookAt(0, 0, 0);

    scene.add(new THREE.HemisphereLight(0xffffff, 0xe7e7e2, 2));

    const keyLight = new THREE.DirectionalLight(0xffffff, 2.2);
    keyLight.position.set(-5, 7, 11);
    scene.add(keyLight);

    const rimLight = new THREE.DirectionalLight(0xffffff, 0.75);
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

    const backboneMaterials = [
      new THREE.MeshStandardMaterial({
        color: 0xd4d4d0,
        roughness: 0.42,
        metalness: 0,
      }),
      new THREE.MeshStandardMaterial({
        color: 0xe1e1de,
        roughness: 0.48,
        metalness: 0,
      }),
    ];

    const baseMaterials = [
      new THREE.MeshStandardMaterial({
        color: 0xd8d8d4,
        roughness: 0.58,
        metalness: 0,
      }),
      new THREE.MeshStandardMaterial({
        color: 0xe3e3e0,
        roughness: 0.62,
        metalness: 0,
      }),
    ];

    const jointMaterials = [
      new THREE.MeshStandardMaterial({
        color: 0xcececa,
        roughness: 0.38,
        metalness: 0,
      }),
      new THREE.MeshStandardMaterial({
        color: 0xdadad6,
        roughness: 0.42,
        metalness: 0,
      }),
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

    function addRod(group, from, to, material, radius) {
      const midpoint = new THREE.Vector3().addVectors(from, to).multiplyScalar(0.5);
      const direction = new THREE.Vector3().subVectors(to, from);
      const length = direction.length();
      const geometry = new THREE.CylinderGeometry(radius, radius, length, 8, 1, false);
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
      const tubeRadius = narrow ? 0.033 : 0.037;
      const rungRadius = narrow ? 0.012 : 0.014;
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
      const sphereGeometry = new THREE.SphereGeometry(tubeRadius * 1.42, 10, 8);

      for (let axisX = -axisLength / 2; axisX <= axisLength / 2; axisX += rungStep) {
        const first = helixPoint(axisX, pitch, radius, 0);
        const second = helixPoint(axisX, pitch, radius, 1);
        const midpoint = new THREE.Vector3().addVectors(first, second).multiplyScalar(0.5);

        addRod(group, first, midpoint, baseMaterials[0], rungRadius);
        addRod(group, midpoint, second, baseMaterials[1], rungRadius);

        const firstJoint = new THREE.Mesh(sphereGeometry, jointMaterials[0]);
        firstJoint.position.copy(first);
        group.add(firstJoint);

        const secondJoint = new THREE.Mesh(sphereGeometry, jointMaterials[1]);
        secondJoint.position.copy(second);
        group.add(secondJoint);
      }

      group.rotation.x = rotation;
      group.rotation.y = pointerX;
      group.rotation.z = pointerY;
      scene.add(group);
      helix = group;

      camera.left = -worldWidth / 2;
      camera.right = worldWidth / 2;
      camera.top = worldHeight / 2;
      camera.bottom = -worldHeight / 2;
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
        rotation = time * 0.0002 + 0.42;
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

(() => {
  const words = document.querySelectorAll('.health-connect-benefit h2 span');
  if (!words.length || !('IntersectionObserver' in window) ||
      window.matchMedia('(prefers-reduced-motion: reduce)').matches) return;

  // Copy stays fully visible without JavaScript or an observer-capable browser.
  const observer = new IntersectionObserver((entries) => {
    for (const entry of entries) {
      if (!entry.isIntersecting) continue;
      entry.target.classList.remove('word-pending');
      observer.unobserve(entry.target);
    }
  }, { rootMargin: '0px 0px -15% 0px', threshold: 0.1 });
  words.forEach((word, index) => {
    word.style.transitionDelay = `${index * 40}ms`;
    word.classList.add('word-pending');
    observer.observe(word);
  });
})();

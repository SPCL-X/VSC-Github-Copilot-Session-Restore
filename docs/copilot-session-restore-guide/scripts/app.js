(async function () {
  const navEl = document.getElementById('site-nav');
  const mainEl = document.getElementById('site-main');
  const errorEl = document.getElementById('load-error');

  try {
    const guideData = await loadGuideData();
    renderGuide(guideData, navEl, mainEl);
    setupNavHighlighting(navEl, mainEl);
  } catch (err) {
    if (errorEl) {
      errorEl.textContent = 'ガイドの読み込みに失敗しました: ' + err.message;
      errorEl.style.display = 'block';
    }
  }
})();

function setupNavHighlighting(navEl, mainEl) {
  const links = Array.prototype.slice.call(navEl.querySelectorAll('a'));
  const sections = Array.prototype.slice.call(mainEl.querySelectorAll('section'));

  function setActive(id) {
    links.forEach((link) => {
      link.classList.toggle('active', link.dataset.targetId === id);
    });
  }

  if (sections.length > 0) {
    setActive(sections[0].id);
  }

  if ('IntersectionObserver' in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            setActive(entry.target.id);
          }
        });
      },
      { rootMargin: '-20% 0px -70% 0px' }
    );
    sections.forEach((section) => observer.observe(section));
  }
}

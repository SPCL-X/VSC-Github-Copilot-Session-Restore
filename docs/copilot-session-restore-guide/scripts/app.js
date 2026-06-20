const LANG_STORAGE_KEY = 'copilotRestoreGuideLang';
const ERROR_MESSAGES = {
  ja: 'ガイドの読み込みに失敗しました: ',
  en: 'Failed to load the guide: '
};

let guideDataAll = null;
let currentLang = 'ja';
let activeObserver = null;

(async function () {
  const navEl = document.getElementById('site-nav');
  const mainEl = document.getElementById('site-main');
  const errorEl = document.getElementById('load-error');

  try {
    guideDataAll = await loadGuideData();
    currentLang = detectInitialLang(guideDataAll);
    setupLangSwitch();
    renderCurrentLang(navEl, mainEl);
  } catch (err) {
    if (errorEl) {
      errorEl.textContent = ERROR_MESSAGES.ja + err.message;
      errorEl.style.display = 'block';
    }
  }
})();

function detectInitialLang(data) {
  const saved = window.localStorage ? window.localStorage.getItem(LANG_STORAGE_KEY) : null;
  if (saved && data[saved]) return saved;
  const browserLang = (navigator.language || 'en').toLowerCase();
  if (browserLang.indexOf('ja') === 0 && data.ja) return 'ja';
  return data.en ? 'en' : Object.keys(data)[0];
}

function setupLangSwitch() {
  const buttons = document.querySelectorAll('#lang-switch button');
  buttons.forEach((btn) => {
    btn.addEventListener('click', () => {
      const lang = btn.dataset.lang;
      if (!guideDataAll[lang] || lang === currentLang) return;
      currentLang = lang;
      if (window.localStorage) {
        window.localStorage.setItem(LANG_STORAGE_KEY, lang);
      }
      renderCurrentLang(document.getElementById('site-nav'), document.getElementById('site-main'));
    });
  });
  updateLangButtons();
}

function updateLangButtons() {
  const buttons = document.querySelectorAll('#lang-switch button');
  buttons.forEach((btn) => {
    btn.classList.toggle('active', btn.dataset.lang === currentLang);
  });
}

function renderCurrentLang(navEl, mainEl) {
  if (activeObserver) {
    activeObserver.disconnect();
    activeObserver = null;
  }
  renderGuide(guideDataAll[currentLang], navEl, mainEl);
  updateLangButtons();
  activeObserver = setupNavHighlighting(navEl, mainEl);
  document.documentElement.lang = currentLang;
}

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
    return observer;
  }
  return null;
}

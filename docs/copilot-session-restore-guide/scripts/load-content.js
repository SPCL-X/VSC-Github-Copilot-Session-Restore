// guide.json の読み込みを試み、file:// 直開き等で fetch が使えない場合は
// guide-data.js が事前に設定する window.__GUIDE_DATA__ にフォールバックする。
async function loadGuideData() {
  try {
    const res = await fetch('content/guide.json', { cache: 'no-store' });
    if (!res.ok) {
      throw new Error('fetch failed with status ' + res.status);
    }
    return await res.json();
  } catch (err) {
    if (window.__GUIDE_DATA__) {
      return window.__GUIDE_DATA__;
    }
    throw err;
  }
}

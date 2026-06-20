// guideData.steps の配列順序だけを唯一の正とし、左ナビと本文を同じ配列から生成する。
// 別々の配列をそれぞれ手動で管理しないため、ナビ順と本文順が構造的にずれない。
function renderGuide(guideData, navEl, mainEl) {
  document.title = guideData.title || 'Guide';

  const titleEl = document.getElementById('site-title');
  if (titleEl) {
    titleEl.textContent = guideData.title || '';
  }

  navEl.innerHTML = '';
  mainEl.innerHTML = '';

  const navList = document.createElement('ul');
  navList.className = 'nav-list';

  guideData.steps.forEach((step) => {
    const navItem = document.createElement('li');
    const navLink = document.createElement('a');
    navLink.href = '#' + step.id;
    navLink.textContent = step.navLabel || step.heading || step.id;
    navLink.dataset.targetId = step.id;
    navItem.appendChild(navLink);
    navList.appendChild(navItem);

    mainEl.appendChild(renderSection(step));
  });

  navEl.appendChild(navList);
}

function renderSection(step) {
  const section = document.createElement('section');
  section.id = step.id;
  section.className = 'guide-section';

  const heading = document.createElement('h2');
  heading.textContent = step.heading || step.navLabel || step.id;
  section.appendChild(heading);

  (step.body || []).forEach((paragraph) => {
    const p = document.createElement('p');
    p.textContent = paragraph;
    section.appendChild(p);
  });

  if (step.command) {
    const pre = document.createElement('pre');
    const code = document.createElement('code');
    code.textContent = step.command;
    pre.appendChild(code);
    section.appendChild(pre);
  }

  if (step.options) {
    section.appendChild(renderOptionsTable(step.options));
  }

  if (step.checks) {
    section.appendChild(renderChecksList(step.checks));
  }

  return section;
}

function renderOptionsTable(options) {
  const table = document.createElement('table');
  table.className = 'options-table';

  const thead = document.createElement('thead');
  const headRow = document.createElement('tr');
  ['オプション', '説明'].forEach((label) => {
    const th = document.createElement('th');
    th.textContent = label;
    headRow.appendChild(th);
  });
  thead.appendChild(headRow);
  table.appendChild(thead);

  const tbody = document.createElement('tbody');
  options.forEach((opt) => {
    const row = document.createElement('tr');
    const nameCell = document.createElement('td');
    nameCell.textContent = opt.name;
    nameCell.className = 'option-name';
    const descCell = document.createElement('td');
    descCell.textContent = opt.desc;
    row.appendChild(nameCell);
    row.appendChild(descCell);
    tbody.appendChild(row);
  });
  table.appendChild(tbody);

  return table;
}

function renderChecksList(checks) {
  const ul = document.createElement('ul');
  ul.className = 'checks-list';
  checks.forEach((check) => {
    const li = document.createElement('li');
    li.textContent = check;
    ul.appendChild(li);
  });
  return ul;
}

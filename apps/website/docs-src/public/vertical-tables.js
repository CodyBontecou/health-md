(() => {
  const tableSelector = '.sl-markdown-content table';
  const tocSelector = 'starlight-toc, mobile-starlight-toc';
  const formatPreferenceKey = 'healthmd-docs-table-format';
  const exportFormats = [
    { id: 'json', label: 'JSON' },
    { id: 'csv', label: 'CSV' },
    { id: 'markdown', label: 'Markdown' },
    { id: 'bases', label: 'Obsidian Bases' },
  ];

  function slugify(value) {
    return value
      .toLowerCase()
      .normalize('NFKD')
      .replace(/[^a-z0-9]+/g, '-')
      .replace(/^-|-$/g, '')
      .slice(0, 64) || 'fields';
  }

  function exportFormatForLabel(label) {
    const value = label.trim().toLowerCase();
    if (/^json(?:\s+paths?)?$/.test(value)) return 'json';
    if (/^csv(?:\s+paths?)?$/.test(value)) return 'csv';
    if (/^markdown(?:\s+paths?)?$/.test(value)) return 'markdown';
    if (/^(?:obsidian\s+)?bases?(?:\s+paths?)?$/.test(value)) return 'bases';
    return undefined;
  }

  function precedingSection(table) {
    const content = table.closest('.sl-markdown-content');
    const headings = content ? [...content.querySelectorAll('h1[id], h2[id], h3[id]')] : [];
    let section;

    headings.forEach((heading) => {
      if (heading.compareDocumentPosition(table) & Node.DOCUMENT_POSITION_FOLLOWING) {
        section = heading;
      }
    });

    return {
      id: section?.id || '_top',
      isOverview: !section || section.tagName === 'H1' || section.id === '_top',
      title: section?.textContent?.trim() || 'Overview',
    };
  }

  function tableColumnTitle(labels) {
    const structuralLabels = labels.filter((label) => !exportFormatForLabel(label));
    const displayLabels = structuralLabels.length > 0 ? structuralLabels : labels;
    if (displayLabels.length === 0) return 'Fields';
    if (displayLabels.length === 1) return displayLabels[0];
    return `${displayLabels[0]} / ${displayLabels[1]}`;
  }

  function selectedFormat() {
    try {
      const stored = localStorage.getItem(formatPreferenceKey);
      if (exportFormats.some((format) => format.id === stored)) return stored;
    } catch {
      // Storage can be unavailable in privacy-restricted contexts.
    }
    return 'json';
  }

  function applyFormatSelection(format, persist = false) {
    if (persist) {
      try {
        localStorage.setItem(formatPreferenceKey, format);
      } catch {
        // The toggle still works for this page when storage is unavailable.
      }
    }

    document.querySelectorAll('.hmd-format-table').forEach((wrapper) => {
      const supported = [...wrapper.querySelectorAll('[data-hmd-format-choice]')]
        .map((button) => button.dataset.hmdFormatChoice);
      const active = supported.includes(format) ? format : supported[0];
      wrapper.dataset.hmdActiveFormat = active;

      wrapper.querySelectorAll('[data-hmd-export-format]').forEach((cell) => {
        cell.classList.toggle('hmd-format-hidden', cell.dataset.hmdExportFormat !== active);
      });
      wrapper.querySelectorAll('[data-hmd-format-choice]').forEach((button) => {
        const isActive = button.dataset.hmdFormatChoice === active;
        button.setAttribute('aria-pressed', String(isActive));
        button.classList.toggle('is-active', isActive);
      });
    });
  }

  function addFormatSwitchers(tableDetails) {
    tableDetails.forEach(({ headerRow, labels, table }) => {
      if (!headerRow) return;

      const formatColumns = labels
        .map((label, index) => ({ format: exportFormatForLabel(label), index }))
        .filter(({ format }) => format);
      const supportedFormats = [...new Set(formatColumns.map(({ format }) => format))];
      if (supportedFormats.length < 2) return;

      formatColumns.forEach(({ format, index }) => {
        headerRow.cells[index]?.setAttribute('data-hmd-export-format', format);
        [...(table.tBodies || [])].forEach((body) => {
          [...body.rows].forEach((row) => {
            row.cells[index]?.setAttribute('data-hmd-export-format', format);
          });
        });
      });

      if (table.closest('.hmd-format-table')) return;

      const wrapper = document.createElement('div');
      wrapper.className = 'hmd-format-table';
      const switcher = document.createElement('div');
      switcher.className = 'hmd-format-switcher';

      const prompt = document.createElement('span');
      prompt.className = 'hmd-format-switcher-label';
      prompt.textContent = 'Format';
      switcher.append(prompt);

      const controls = document.createElement('div');
      controls.className = 'hmd-format-options';
      controls.setAttribute('role', 'group');
      controls.setAttribute('aria-label', 'Export format shown in this table');

      exportFormats
        .filter(({ id }) => supportedFormats.includes(id))
        .forEach(({ id, label }) => {
          const button = document.createElement('button');
          button.type = 'button';
          button.dataset.hmdFormatChoice = id;
          button.textContent = label;
          button.setAttribute('aria-controls', table.id);
          button.addEventListener('click', () => applyFormatSelection(id, true));
          controls.append(button);
        });

      switcher.append(controls);
      table.parentNode?.insertBefore(wrapper, table);
      wrapper.append(switcher, table);
    });

    applyFormatSelection(selectedFormat());
  }

  function buildKeyGroups(tableDetails) {
    const groups = new Map();

    tableDetails.forEach(({ labels, table }) => {
      const keyColumn = labels.findIndex((label) => /^(?:canonical )?key$/i.test(label));
      const keyListColumn = labels.findIndex((label) => /^all dictionary keys$/i.test(label));
      if (keyColumn < 0 && keyListColumn < 0) return;

      const rows = [...(table.tBodies || [])].flatMap((body) => [...body.rows]);
      const keyEntries = [];
      rows.forEach((row, rowIndex) => {
        if (keyColumn >= 0) {
          const key = row.cells[keyColumn]?.textContent?.trim();
          if (!key) return;
          const id = `${table.id}-key-${slugify(key)}-${rowIndex + 1}`;
          row.id = id;
          row.dataset.hmdKey = key;
          keyEntries.push({ id, key });
          return;
        }

        const cell = row.cells[keyListColumn];
        if (!cell) return;
        const existingAnchors = [...cell.querySelectorAll('[data-hmd-key]')];
        const keys = existingAnchors.length > 0
          ? existingAnchors.map((anchor) => anchor.dataset.hmdKey)
          : (() => {
              const clone = cell.cloneNode(true);
              clone.querySelectorAll('br').forEach((breakElement) => breakElement.replaceWith('\n'));
              return clone.textContent.split('\n').map((key) => key.trim()).filter(Boolean);
            })();

        if (existingAnchors.length === 0) {
          cell.replaceChildren();
          keys.forEach((key, keyIndex) => {
            const anchor = document.createElement('span');
            anchor.className = 'hmd-key-anchor';
            anchor.dataset.hmdKey = key;
            anchor.id = `${table.id}-key-${slugify(key)}-${rowIndex + 1}-${keyIndex + 1}`;
            anchor.textContent = key;
            cell.append(anchor);
          });
        }

        [...cell.querySelectorAll('[data-hmd-key]')].forEach((anchor) => {
          keyEntries.push({ id: anchor.id, key: anchor.dataset.hmdKey });
        });
      });

      const uniqueKeys = [...new Map(keyEntries.map((entry) => [entry.key, entry])).values()]
        .sort((left, right) => left.key.localeCompare(right.key));
      if (uniqueKeys.length === 0) return;

      if (keyListColumn >= 0) {
        const dailyColumn = labels.findIndex((label) => /^daily aggregation$/i.test(label));
        const primaryColumn = labels.findIndex((label) => /^roll-up primary$/i.test(label));
        const candidates = rows.map((row) => {
          const daily = row.cells[dailyColumn]?.textContent?.trim();
          const primary = row.cells[primaryColumn]?.textContent?.trim();
          const firstKey = row.cells[keyListColumn]?.querySelector('[data-hmd-key]')?.dataset.hmdKey;
          return { base: `${daily} → ${primary}`, firstKey, row };
        });
        const occurrences = new Map();
        candidates.forEach(({ base }) => occurrences.set(base, (occurrences.get(base) || 0) + 1));
        const rules = candidates.map(({ base, firstKey, row }, rowIndex) => {
          const key = occurrences.get(base) > 1 && firstKey ? `${base} — ${firstKey}` : base;
          const id = `${table.id}-rule-${slugify(key)}-${rowIndex + 1}`;
          row.id = id;
          row.dataset.hmdRule = key;
          return { id, key };
        });
        const entries = [...rules, ...uniqueKeys];
        groups.set(table.id, {
          countLabel: `${rules.length}+${uniqueKeys.length}`,
          entries,
          label: 'Roll-up rules and keys',
          sections: [
            { entries: rules, label: 'Aggregation rules' },
            { entries: uniqueKeys, label: 'Metric keys' },
          ],
        });
        return;
      }

      const label = /^canonical key$/i.test(labels[keyColumn]) ? 'Canonical keys' : 'Keys';
      groups.set(table.id, {
        entries: uniqueKeys,
        label,
        sections: [{ entries: uniqueKeys, label }],
      });
    });

    return groups;
  }

  function addKeyPanel(container, group, count, toc) {
    const label = document.createElement('div');
    label.className = 'hmd-nested-key-label';
    label.textContent = group.label;
    container.append(label);

    const search = document.createElement('input');
    search.type = 'search';
    search.className = 'hmd-key-filter';
    search.placeholder = `Filter ${group.label.toLowerCase()}…`;
    search.setAttribute('aria-label', `Filter ${group.label.toLowerCase()}`);
    container.append(search);

    const list = document.createElement('ul');
    list.className = 'hmd-key-list';
    const indexedItems = [];
    const sectionRecords = [];
    group.sections.forEach((section) => {
      const sectionLabel = document.createElement('li');
      sectionLabel.className = 'hmd-key-group-label';
      sectionLabel.textContent = section.label;
      sectionLabel.hidden = group.sections.length === 1;
      list.append(sectionLabel);

      const sectionItems = [];
      section.entries.forEach((entry) => {
        const item = document.createElement('li');
        item.dataset.hmdKeyItem = entry.key.toLowerCase();
        const link = document.createElement('a');
        link.href = `#${entry.id}`;
        link.textContent = entry.key;
        link.addEventListener('click', () => {
          toc.querySelector('details#starlight__mobile-toc')?.removeAttribute('open');
        });
        item.append(link);
        list.append(item);
        indexedItems.push(item);
        sectionItems.push(item);
      });
      sectionRecords.push({ label: sectionLabel, items: sectionItems });
    });
    container.append(list);

    const empty = document.createElement('p');
    empty.className = 'hmd-key-filter-empty';
    empty.textContent = `No matching ${group.label.toLowerCase()}.`;
    empty.hidden = true;
    container.append(empty);

    search.addEventListener('input', () => {
      const query = search.value.trim().toLowerCase();
      let visible = 0;
      indexedItems.forEach((item) => {
        const matches = !query || item.dataset.hmdKeyItem.includes(query);
        item.hidden = !matches;
        if (matches) visible += 1;
      });
      sectionRecords.forEach((section) => {
        section.label.hidden = group.sections.length === 1 || !section.items.some((item) => !item.hidden);
      });
      count.textContent = query ? `${visible}/${group.entries.length}` : (group.countLabel || String(group.entries.length));
      empty.hidden = visible !== 0;
    });
    search.addEventListener('keydown', (event) => {
      if (event.key === 'Escape' && search.value) {
        search.value = '';
        search.dispatchEvent(new Event('input'));
      }
    });
  }

  function addTableIndexes(entries, keyGroups) {
    document.querySelectorAll('[data-hmd-table-index]').forEach((index) => index.remove());
    if (entries.length === 0) return;

    const hashTarget = location.hash ? document.getElementById(decodeURIComponent(location.hash.slice(1))) : undefined;
    const hashTableID = hashTarget?.closest('table')?.id;
    const defaultTableID = hashTableID || keyGroups.keys().next().value;

    document.querySelectorAll(tocSelector).forEach((toc) => {
      const nav = toc.querySelector('nav');
      if (!nav) return;

      const details = document.createElement('details');
      details.className = 'hmd-table-index';
      details.dataset.hmdTableIndex = '';
      details.open = toc.matches('starlight-toc') && keyGroups.size > 0;

      const summary = document.createElement('summary');
      summary.append('Tables');
      const count = document.createElement('span');
      count.textContent = String(entries.length);
      count.setAttribute('aria-label', `${entries.length} tables`);
      summary.append(count);
      details.append(summary);

      const list = document.createElement('ul');
      entries.forEach((entry) => {
        const item = document.createElement('li');
        const keyGroup = keyGroups.get(entry.id);
        if (!keyGroup) {
          const link = document.createElement('a');
          link.href = `#${entry.id}`;
          link.textContent = entry.title;
          link.addEventListener('click', () => {
            toc.querySelector('details#starlight__mobile-toc')?.removeAttribute('open');
          });
          item.append(link);
          list.append(item);
          return;
        }

        const tableDetails = document.createElement('details');
        tableDetails.className = 'hmd-table-key-group';
        tableDetails.dataset.hmdTableKeyGroup = entry.id;
        tableDetails.open = defaultTableID === entry.id;

        const tableSummary = document.createElement('summary');
        const tableLink = document.createElement('a');
        tableLink.href = `#${entry.id}`;
        tableLink.textContent = entry.title;
        tableLink.addEventListener('click', (event) => {
          event.stopPropagation();
          if (toc.matches('mobile-starlight-toc') && !tableDetails.open) {
            event.preventDefault();
            tableDetails.open = true;
            return;
          }
          tableDetails.open = true;
          toc.querySelector('details#starlight__mobile-toc')?.removeAttribute('open');
        });
        tableSummary.append(tableLink);
        const keyCount = document.createElement('span');
        keyCount.textContent = keyGroup.countLabel || String(keyGroup.entries.length);
        keyCount.setAttribute('aria-label', `${keyGroup.entries.length} ${keyGroup.label.toLowerCase()}`);
        tableSummary.append(keyCount);
        tableDetails.append(tableSummary);
        addKeyPanel(tableDetails, keyGroup, keyCount, toc);
        tableDetails.addEventListener('toggle', () => {
          if (!tableDetails.open) return;
          list.querySelectorAll('.hmd-table-key-group').forEach((other) => {
            if (other !== tableDetails) other.open = false;
          });
        });
        item.append(tableDetails);
        list.append(item);
      });
      details.append(list);

      const destination = toc.matches('mobile-starlight-toc')
        ? toc.querySelector('.dropdown')
        : nav;
      destination?.append(details);
    });

    if (hashTarget?.dataset.hmdKey || hashTarget?.dataset.hmdRule) {
      requestAnimationFrame(() => hashTarget.scrollIntoView({ block: 'start' }));
    }
  }

  function makeTablesVertical(root = document) {
    const tables = [...root.querySelectorAll(tableSelector)];
    const sectionCounts = new Map();
    const tableDetails = tables.map((table) => {
      const headerRow = table.tHead?.rows[table.tHead.rows.length - 1];
      const labels = headerRow
        ? [...headerRow.cells].map((cell, index) => {
            cell.scope = cell.scope || 'col';
            return cell.textContent?.trim() || `Column ${index + 1}`;
          })
        : [];
      const section = precedingSection(table);
      sectionCounts.set(section.id, (sectionCounts.get(section.id) || 0) + 1);
      return { headerRow, labels, section, table };
    });

    const entries = tableDetails.map(({ labels, section, table }, index) => {
      if (!table.classList.contains('hmd-vertical-table')) {
        [...(table.tBodies || [])].forEach((body) => {
          [...body.rows].forEach((row) => {
            [...row.cells].forEach((cell, cellIndex) => {
              cell.dataset.label = labels[cellIndex] || `Column ${cellIndex + 1}`;
            });
          });
        });
        table.classList.add('hmd-vertical-table');
      }

      const title = !section.isOverview && sectionCounts.get(section.id) === 1
        ? section.title
        : `${section.isOverview ? '' : `${section.title}: `}${tableColumnTitle(labels)}`;
      const id = `table-${slugify(title)}-${index + 1}`;
      table.id = id;
      table.setAttribute('aria-label', title);

      return { id, title };
    });

    const keyGroups = buildKeyGroups(tableDetails);
    addFormatSwitchers(tableDetails);
    addTableIndexes(entries, keyGroups);
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => makeTablesVertical(), { once: true });
  } else {
    makeTablesVertical();
  }

  document.addEventListener('astro:page-load', () => makeTablesVertical());
})();

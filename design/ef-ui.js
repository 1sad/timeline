/* ============================================================
   Variants E + F — sheets, category manager, exact-times editor,
   and the Tracks popover used when F Compact hides the gutter.
   ============================================================ */

/* ---------- Tracks popover ---------- */
let efTrackPopEl = null;

function closeEFTrackPop() {
  state.efTrackPop = false;
  if (efTrackPopEl) {
    efTrackPopEl.remove();
    efTrackPopEl = null;
  }
}

function openEFTrackPop() {
  closeEFTrackPop();
  if (!efIs()) return;

  const pop = el('div', 'trackpop');
  pop.addEventListener('pointerdown', e => e.stopPropagation());
  pop.appendChild(el('h4', '', 'Tracks'));

  for (const t of TRACKS) {
    const open = state.trackOpen[t.id] !== false;
    const row = el('div', 'tp-row');
    const dot = el('span', 'dot');
    dot.style.setProperty('--c', t.color);
    row.appendChild(dot);
    row.appendChild(el('span', 'nm', t.name || 'Untitled'));
    const btn = el('button', '', open ? '▾ open' : '▸ closed');
    btn.type = 'button';
    btn.title = (open ? 'Collapse ' : 'Expand ') + (t.name || 'track');
    btn.addEventListener('click', e => {
      e.stopPropagation();
      state.trackOpen[t.id] = !open;
      renderAll();
      openEFTrackPop();
    });
    row.appendChild(btn);
    pop.appendChild(row);
  }

  const foot = el('div', 'tp-foot');
  const all = el('button', '', 'Open all');
  all.type = 'button';
  all.addEventListener('click', e => {
    e.stopPropagation();
    for (const t of TRACKS) state.trackOpen[t.id] = true;
    renderAll();
    openEFTrackPop();
  });
  const none = el('button', '', 'Close all');
  none.type = 'button';
  none.addEventListener('click', e => {
    e.stopPropagation();
    for (const t of TRACKS) state.trackOpen[t.id] = false;
    renderAll();
    openEFTrackPop();
  });
  foot.appendChild(all);
  foot.appendChild(none);
  pop.appendChild(foot);

  pop.style.top = (efDom.viewBar.offsetTop + efDom.viewBar.offsetHeight + 5) + 'px';
  pop.style.left = '10px';
  pop.style.maxHeight = '58vh';
  pop.style.overflow = 'auto';

  const app = dom.device.querySelector('.app');
  app.appendChild(pop);
  efTrackPopEl = pop;
  state.efTrackPop = true;
}

efDom.tracksBtn.addEventListener('click', e => {
  e.stopPropagation();
  if (!efIs()) return;
  if (state.variant === 'G') {
    state.gNamesHidden = !state.gNamesHidden;
    closeEFTrackPop();
    renderAll();
    return;
  }
  if (state.efTrackPop) closeEFTrackPop();
  else openEFTrackPop();
});

document.addEventListener('pointerdown', e => {
  if (!state.efTrackPop) return;
  if (efTrackPopEl && efTrackPopEl.contains(e.target)) return;
  if (efDom.tracksBtn.contains(e.target)) return;
  closeEFTrackPop();
}, true);

/* ---------- category manager ---------- */
function closeEFSheets() {
  state.efModal = null;
  state.efPaletteFor = null;
  state.efConfirmDel = null;
  if (efDom.modalRoot) {
    efDom.modalRoot.innerHTML = '';
    efDom.modalRoot.classList.remove('open');
  }
}

function openEFCategories() {
  if (!efIs()) return;
  closeEFTrackPop();
  state.efModal = 'cat';
  state.efPaletteFor = null;
  state.efConfirmDel = null;
  efRenderCategorySheet();
}

function efCategoryItem(t, fixed) {
  const item = el('div', 'cat-item' + (fixed ? ' cat-fixed' : ''));
  item.dataset.cat = t.id;

  const row = el('div', 'cat-row');
  let swatch;
  if (fixed) {
    swatch = el('div', 'swatch');
  } else {
    swatch = el('button', 'swatch');
    swatch.type = 'button';
    swatch.title = 'Change colour';
    swatch.addEventListener('click', e => {
      e.stopPropagation();
      state.efPaletteFor = state.efPaletteFor === t.id ? null : t.id;
      state.efConfirmDel = null;
      efRenderCategorySheet();
    });
  }
  swatch.style.setProperty('--c', t.color);
  row.appendChild(swatch);

  if (fixed) {
    const name = el('div', 'cat-name', t.name);
    name.style.opacity = '.75';
    row.appendChild(name);
    row.appendChild(el('span', 'cat-fixed-tag', 'built-in'));
  } else {
    const input = document.createElement('input');
    input.className = 'cat-name';
    input.value = t.name;
    input.maxLength = 40;
    input.dataset.catName = t.id;
    input.addEventListener('input', () => {
      t.name = input.value;
      renderAll();
    });
    input.addEventListener('blur', () => {
      const v = input.value.trim();
      t.name = v || 'Untitled';
      input.value = t.name;
      renderAll();
    });
    input.addEventListener('keydown', e => {
      if (e.key === 'Enter') {
        e.preventDefault();
        input.blur();
      }
    });
    row.appendChild(input);
  }

  const count = efCountFor(t.id);
  row.appendChild(el('span', 'cat-count', count + (count === 1 ? ' block' : ' blocks')));

  if (!fixed) {
    const del = el('button', 'cat-del', '✕');
    del.type = 'button';
    del.title = 'Delete category';
    del.addEventListener('click', e => {
      e.stopPropagation();
      if (efCountFor(t.id) > 0) {
        state.efConfirmDel = t.id;
        state.efPaletteFor = null;
        efRenderCategorySheet();
      } else {
        efDeleteCategory(t.id);
      }
    });
    row.appendChild(del);
  }

  item.appendChild(row);

  if (!fixed && state.efPaletteFor === t.id) {
    const pal = el('div', 'palette');
    for (const c of EF_PALETTE) {
      const b = el('button', c === t.color ? 'on' : '');
      b.type = 'button';
      b.style.setProperty('--c', c);
      b.title = c;
      b.addEventListener('click', e => {
        e.stopPropagation();
        t.color = c;
        state.efPaletteFor = null;
        renderAll();
        efRenderCategorySheet();
      });
      pal.appendChild(b);
    }
    item.appendChild(pal);
  }

  if (!fixed && state.efConfirmDel === t.id) {
    const n = efCountFor(t.id);
    const conf = el('div', 'cat-confirm');
    conf.appendChild(el('span', '', 'Delete “' + t.name + '”? ' + n +
      (n === 1 ? ' block' : ' blocks') + ' will move to Uncategorized.'));
    const cancel = el('button', 'btn-ghost', 'Cancel');
    cancel.type = 'button';
    cancel.addEventListener('click', e => {
      e.stopPropagation();
      state.efConfirmDel = null;
      efRenderCategorySheet();
    });
    const yes = el('button', 'btn-danger', 'Delete');
    yes.type = 'button';
    yes.addEventListener('click', e => {
      e.stopPropagation();
      efDeleteCategory(t.id);
    });
    conf.appendChild(cancel);
    conf.appendChild(yes);
    item.appendChild(conf);
  }

  return item;
}

/* ---------- simple JSON sync ---------- */
function efExportSyncFile() {
  const data = {
    format: 'timeline-sync-v1',
    exportedAt: new Date().toISOString(),
    tracks: TRACKS.map(t => ({
      id: t.id,
      name: t.name,
      color: t.color,
      ...(t.fixed ? { fixed: true } : {})
    })),
    blocks: blocks.map(b => ({
      id: b.id,
      track: b.track,
      title: b.title,
      start: b.start,
      end: b.end,
      ...(b.type ? { type: b.type } : {})
    })),
    trackOpen: { ...state.trackOpen }
  };

  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = 'timeline-sync-' + new Date().toISOString().slice(0, 10) + '.json';
  document.body.appendChild(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
  toast('Exported categories and blocks');
}

function efImportSyncFile(file) {
  if (!file) return;
  const reader = new FileReader();
  reader.onerror = () => toast('Could not read that sync file');
  reader.onload = () => {
    try {
      const raw = JSON.parse(String(reader.result));
      if (!raw || !Array.isArray(raw.tracks) || !Array.isArray(raw.blocks)) {
        throw new Error('Not a Timeline sync file');
      }

      const seenTracks = new Set();
      const nextTracks = [];
      for (const t of raw.tracks) {
        if (!t || typeof t.id !== 'string' || !t.id || seenTracks.has(t.id)) continue;
        seenTracks.add(t.id);
        nextTracks.push({
          id: t.id,
          name: String(t.name || 'Untitled'),
          color: /^#[0-9a-f]{6}$/i.test(t.color || '') ? t.color : '#7c8698',
          ...(t.id === 'uncat' ? { fixed: true } : {})
        });
      }

      const trackIds = new Set(nextTracks.map(t => t.id));
      const seenBlocks = new Set();
      const nextBlocks = [];
      let nextId = 1;
      for (const b of raw.blocks) {
        if (!b) continue;
        const start = Number(b.start);
        const end = Number(b.end);
        if (!Number.isFinite(start) || !Number.isFinite(end) || end <= start) continue;

        let id = Number(b.id);
        if (!Number.isInteger(id) || id <= 0 || seenBlocks.has(id)) {
          while (seenBlocks.has(nextId)) nextId++;
          id = nextId;
        }
        seenBlocks.add(id);
        nextId = Math.max(nextId, id + 1);

        const track = typeof b.track === 'string' && trackIds.has(b.track) ? b.track : 'uncat';
        nextBlocks.push({
          id,
          track,
          title: String(b.title || 'Untitled'),
          start,
          end,
          ...(b.type === 'zone' ? { type: 'zone' } : {})
        });
      }

      const beforeBlocks = blocks.map(b => ({ ...b }));
      const beforeTracks = TRACKS.map(t => ({ ...t }));
      const beforeOpen = { ...state.trackOpen };

      TRACKS.length = 0;
      for (const t of nextTracks) TRACKS.push(t);
      blocks.length = 0;
      for (const b of nextBlocks) blocks.push(b);
      uid = nextId;
      state.selectedId = null;
      state.efPaletteFor = null;
      state.efConfirmDel = null;
      state.trackOpen = {};
      for (const t of TRACKS) {
        state.trackOpen[t.id] = !raw.trackOpen || raw.trackOpen[t.id] !== false;
      }

      efEnsureUncat();
      efSyncTrackById();
      state.undo.push({
        snapshot: beforeBlocks,
        tracks: beforeTracks,
        trackOpen: beforeOpen,
        label: 'Imported sync file'
      });
      if (state.undo.length > 25) state.undo.shift();

      renderAll();
      efRenderCategorySheet();
      toast('Imported ' + nextBlocks.length + ' blocks · ' + TRACKS.length + ' categories');
    } catch (err) {
      toast('Import failed — choose a Timeline sync file');
    }
  };
  reader.readAsText(file);
}

function efRenderSyncSection(body) {
  const box = el('div', 'cat-sync');
  const head = el('div', 'cat-sync-head');
  head.appendChild(el('div', 'cat-sync-title', 'Sync'));
  head.appendChild(el('div', 'cat-sync-copy', 'Write categories and blocks to a small JSON file, or import one from another device.'));
  box.appendChild(head);

  const row = el('div', 'cat-sync-actions');
  const exp = el('button', 'btn-ghost', 'Export .json');
  exp.type = 'button';
  exp.title = 'Download a portable Timeline JSON file';
  exp.addEventListener('click', e => {
    e.stopPropagation();
    efExportSyncFile();
  });
  const imp = el('button', 'btn-ghost', 'Import .json');
  imp.type = 'button';
  imp.title = 'Replace categories and blocks from a Timeline JSON file';
  const picker = document.createElement('input');
  picker.type = 'file';
  picker.accept = '.json,application/json';
  picker.hidden = true;
  picker.addEventListener('change', () => {
    const file = picker.files && picker.files[0];
    if (file) efImportSyncFile(file);
    picker.value = '';
  });
  imp.addEventListener('click', e => {
    e.stopPropagation();
    picker.click();
  });
  row.appendChild(exp);
  row.appendChild(imp);
  box.appendChild(row);
  box.appendChild(picker);
  body.appendChild(box);
}

function efRenderCategorySheet() {
  if (!efDom.modalRoot) return;
  const oldBody = efDom.modalRoot.querySelector('.sheet-body');
  const scroll = oldBody ? oldBody.scrollTop : 0;

  efDom.modalRoot.innerHTML = '';
  efDom.modalRoot.classList.add('open');

  const back = el('div', 'modal-backdrop');
  back.addEventListener('click', e => {
    if (e.target === back) {
      closeEFSheets();
      renderAll();
    }
  });

  const sheet = el('div', 'sheet');
  sheet.addEventListener('pointerdown', e => e.stopPropagation());

  const head = el('div', 'sheet-head');
  const hleft = el('div');
  hleft.appendChild(el('div', 'sheet-kicker', 'Categories'));
  hleft.appendChild(el('div', 'sheet-title', 'Your tracks'));
  hleft.appendChild(el('div', 'sheet-sub', 'Rename, recolour, add or delete. Zero categories is allowed.'));
  head.appendChild(hleft);

  const x = el('button', 'xbtn', '✕');
  x.type = 'button';
  x.title = 'Close';
  x.addEventListener('click', () => { closeEFSheets(); renderAll(); });
  head.appendChild(x);
  sheet.appendChild(head);

  const body = el('div', 'sheet-body');
  const list = el('div', 'cat-list');

  const editable = TRACKS.filter(t => !t.fixed);
  if (!editable.length) {
    const empty = el('div', 'cat-empty');
    empty.innerHTML = 'No categories yet.<br><b>Every block is Uncategorized.</b><br>Add one below whenever you want.';
    list.appendChild(empty);
  }
  for (const t of editable) list.appendChild(efCategoryItem(t, false));

  const uncat = TRACKS.find(t => t.fixed);
  if (uncat) list.appendChild(efCategoryItem(uncat, true));

  body.appendChild(list);

  const addWrap = el('div', 'cat-add');
  const add = el('button', '', '＋ New category');
  add.type = 'button';
  add.addEventListener('click', () => efAddCategory());
  addWrap.appendChild(add);
  body.appendChild(addWrap);
  efRenderSyncSection(body);
  sheet.appendChild(body);

  const foot = el('div', 'sheet-foot');
  foot.appendChild(el('span', 'note', 'Deleting a category moves its blocks to Uncategorized. Changes apply immediately.'));
  const done = el('button', 'btn-primary', 'Done');
  done.type = 'button';
  done.addEventListener('click', () => { closeEFSheets(); renderAll(); });
  foot.appendChild(done);
  sheet.appendChild(foot);

  back.appendChild(sheet);
  efDom.modalRoot.appendChild(back);

  if (scroll) {
    requestAnimationFrame(() => {
      const b = efDom.modalRoot.querySelector('.sheet-body');
      if (b) b.scrollTop = scroll;
    });
  }
}

let efCatSeq = 1;

function efAddCategory() {
  let id;
  do { id = 'cat-' + (efCatSeq++); } while (TRACKS.some(t => t.id === id));
  const used = new Set(TRACKS.map(t => t.color));
  const color = EF_PALETTE.find(c => !used.has(c)) || EF_PALETTE[Math.floor(Math.random() * EF_PALETTE.length)];
  const t = { id, name: 'New category', color };

  const uncatIdx = TRACKS.findIndex(x => x.fixed);
  if (uncatIdx >= 0) TRACKS.splice(uncatIdx, 0, t);
  else TRACKS.push(t);

  state.trackOpen[id] = true;
  efSyncTrackById();
  renderAll();
  efRenderCategorySheet();

  setTimeout(() => {
    const inp = efDom.modalRoot.querySelector('[data-cat-name="' + id + '"]');
    if (inp) {
      inp.focus();
      inp.select();
      inp.scrollIntoView({ block: 'center' });
    }
  }, 40);
}

function efPushCategoryUndo(label) {
  state.undo.push({
    snapshot: blocks.map(b => ({ ...b })),
    tracks: TRACKS.map(t => ({ ...t })),
    trackOpen: { ...state.trackOpen },
    label
  });
  if (state.undo.length > 25) state.undo.shift();
  renderChrome();
}

function efDeleteCategory(id) {
  const idx = TRACKS.findIndex(t => t.id === id && !t.fixed);
  if (idx < 0) return;
  const cat = TRACKS[idx];
  efPushCategoryUndo('Deleted category “' + cat.name + '”');
  let moved = 0;
  for (const b of blocks) {
    if (efTrackId(b) === id) {
      b.track = 'uncat';
      moved++;
    }
  }
  TRACKS.splice(idx, 1);
  delete state.trackOpen[id];
  state.efConfirmDel = null;
  state.efPaletteFor = null;

  efEnsureUncat();
  efSyncTrackById();
  renderAll();
  toast('“' + cat.name + '” deleted' + (moved
    ? ' · ' + moved + (moved === 1 ? ' block' : ' blocks') + ' moved to Uncategorized'
    : ''), true);
  efRenderCategorySheet();
}

/* ---------- exact-times editor ---------- */
function efPad(n) {
  return String(n).padStart(2, '0');
}

function efDateStr(ts) {
  const d = new Date(ts);
  return d.getFullYear() + '-' + efPad(d.getMonth() + 1) + '-' + efPad(d.getDate());
}

function efTimeStr(ts) {
  const d = new Date(ts);
  return efPad(d.getHours()) + ':' + efPad(d.getMinutes());
}

function efField(label, input) {
  const f = el('div', 'field');
  f.appendChild(el('label', '', label));
  f.appendChild(input);
  return f;
}

function openEFEditor() {
  if (!efIs()) return;
  if (state.locked) {
    toast('Layout is locked — unlock to edit times');
    return;
  }
  const b = blocks.find(x => x.id === state.selectedId);
  if (!b) return;
  closeEFTrackPop();
  state.efModal = 'edit';
  efRenderEditSheet(b);
}

function efRenderEditSheet(block) {
  if (!efDom.modalRoot) return;
  efDom.modalRoot.innerHTML = '';
  efDom.modalRoot.classList.add('open');

  const back = el('div', 'modal-backdrop');
  back.addEventListener('click', e => {
    if (e.target === back) {
      closeEFSheets();
      renderAll();
    }
  });

  const sheet = el('div', 'sheet');
  sheet.addEventListener('pointerdown', e => e.stopPropagation());

  const tid = efTrackId(block);
  const track = TRACK_BY_ID[tid] || EF_UNCAT;

  const head = el('div', 'sheet-head');
  const hleft = el('div');
  hleft.appendChild(el('div', 'sheet-kicker', 'Exact times'));
  hleft.appendChild(el('div', 'sheet-title', block.title));
  hleft.appendChild(el('div', 'sheet-sub', track.name + ' · ' + fmtTime(block.start) + '–' + fmtTime(block.end)));
  head.appendChild(hleft);

  const x = el('button', 'xbtn', '✕');
  x.type = 'button';
  x.title = 'Close';
  x.addEventListener('click', () => { closeEFSheets(); renderAll(); });
  head.appendChild(x);
  sheet.appendChild(head);

  const body = el('div', 'sheet-body');

  const tip = el('div', 'sheet-tip',
    'Numeric fallback for when a block is too small to drag. Change the fields directly, or use the quick duration buttons.');
  body.appendChild(tip);

  const titleIn = document.createElement('input');
  titleIn.type = 'text';
  titleIn.value = block.title;
  titleIn.maxLength = 80;
  body.appendChild(efField('Title', titleIn));

  const catSel = document.createElement('select');
  for (const t of TRACKS.filter(x => !x.fixed)) {
    const o = document.createElement('option');
    o.value = t.id;
    o.textContent = t.name || 'Untitled';
    catSel.appendChild(o);
  }
  const uncatOpt = document.createElement('option');
  uncatOpt.value = 'uncat';
  uncatOpt.textContent = 'Uncategorized';
  catSel.appendChild(uncatOpt);
  catSel.value = tid;
  body.appendChild(efField('Category', catSel));

  const startDate = document.createElement('input');
  startDate.type = 'date';
  startDate.value = efDateStr(block.start);
  const startTime = document.createElement('input');
  startTime.type = 'time';
  startTime.step = '60';
  startTime.value = efTimeStr(block.start);

  const endDate = document.createElement('input');
  endDate.type = 'date';
  endDate.value = efDateStr(block.end);
  const endTime = document.createElement('input');
  endTime.type = 'time';
  endTime.step = '60';
  endTime.value = efTimeStr(block.end);

  const startRow = el('div', 'field-row');
  startRow.appendChild(efField('Start date', startDate));
  startRow.appendChild(efField('Start time', startTime));
  body.appendChild(startRow);

  const endRow = el('div', 'field-row');
  endRow.appendChild(efField('End date', endDate));
  endRow.appendChild(efField('End time', endTime));
  body.appendChild(endRow);

  const dur = el('div', 'durline');
  dur.appendChild(el('span', '', 'Duration'));
  const durVal = el('b', '', '—');
  dur.appendChild(durVal);
  body.appendChild(dur);

  const quick = el('div', 'quickrow');
  for (const min of [15, 30, 60, 120]) {
    const b = el('button', '', '+' + (min < 60 ? min + 'm' : (min / 60) + 'h'));
    b.type = 'button';
    b.addEventListener('click', () => {
      const s = new Date(startDate.value + 'T' + (startTime.value || '00:00')).getTime();
      if (!Number.isFinite(s)) return;
      const e = s + min * 60000;
      endDate.value = efDateStr(e);
      endTime.value = efTimeStr(e);
      refresh();
    });
    quick.appendChild(b);
  }
  body.appendChild(quick);

  const err = el('div', 'err');
  body.appendChild(err);
  sheet.appendChild(body);

  function readTimes() {
    const s = new Date(startDate.value + 'T' + (startTime.value || '00:00')).getTime();
    const e = new Date(endDate.value + 'T' + (endTime.value || '00:00')).getTime();
    return { s, e };
  }

  const foot = el('div', 'sheet-foot');
  foot.appendChild(el('span', 'note', 'Changes are one undo step.'));
  const cancel = el('button', 'btn-ghost', 'Cancel');
  cancel.type = 'button';
  cancel.addEventListener('click', () => { closeEFSheets(); renderAll(); });

  const save = el('button', 'btn-primary', 'Save');
  save.type = 'button';

  function refresh() {
    const { s, e } = readTimes();
    const valid = Number.isFinite(s) && Number.isFinite(e) && e > s;
    if (Number.isFinite(s) && Number.isFinite(e) && e <= s) {
      err.textContent = 'End must be after start.';
    } else if (!Number.isFinite(s) || !Number.isFinite(e)) {
      err.textContent = 'Enter a valid date and time.';
    } else {
      err.textContent = '';
    }
    durVal.textContent = valid ? fmtDur(e - s) : '—';
    save.disabled = !valid;
    save.style.opacity = valid ? '1' : '.45';
  }

  for (const inp of [startDate, startTime, endDate, endTime]) {
    inp.addEventListener('input', refresh);
    inp.addEventListener('change', refresh);
  }

  save.addEventListener('click', () => {
    const { s, e } = readTimes();
    if (!Number.isFinite(s) || !Number.isFinite(e) || e <= s) return;

    const snapshot = blocks.map(x => ({ ...x }));
    block.title = titleIn.value.trim() || 'Untitled';
    block.start = s;
    block.end = e;

    const chosen = catSel.value;
    if (chosen === 'uncat') block.track = 'uncat';
    else if (TRACKS.some(t => t.id === chosen)) block.track = chosen;

    efEnsureUncat();
    efSyncTrackById();
    pushUndo(snapshot, 'Edited ' + block.title);
    closeEFSheets();
    state.selectedId = block.id;
    renderAll();
    toast('Saved ' + block.title + ' · ' + fmtTime(s) + '–' + fmtTime(e), true);
  });

  foot.appendChild(cancel);
  foot.appendChild(save);
  sheet.appendChild(foot);

  back.appendChild(sheet);
  efDom.modalRoot.appendChild(back);
  refresh();
}

/* ---------- wiring ---------- */
efDom.editBtn.addEventListener('click', () => openEFEditor());

const oldTplBtn = dom.tplBtn;
const newTplBtn = oldTplBtn.cloneNode(true);
oldTplBtn.replaceWith(newTplBtn);
dom.tplBtn = newTplBtn;
newTplBtn.addEventListener('click', () => {
  if (efIs()) openEFCategories();
  else toast('Templates — saved presets you stamp onto the timeline');
});

window.addEventListener('keydown', e => {
  if (e.key !== 'Escape') return;
  if (state.efModal) {
    closeEFSheets();
    renderAll();
    e.preventDefault();
    e.stopImmediatePropagation();
    return;
  }
  if (state.efTrackPop) {
    closeEFTrackPop();
    e.preventDefault();
    e.stopImmediatePropagation();
  }
}, true);

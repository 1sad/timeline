/* ============================================================
   Variants E + F — core rendering and timeline behaviour
   E: header-first selection, no row movement.
   F: selected bar expands in place, rows below move.
   Loaded after app.js + interact.js; A–D fall through untouched.
   ============================================================ */

const EF_UNCAT = { id: 'uncat', name: 'Uncategorized', color: '#7c8698', fixed: true };
const EF_PALETTE = [
  '#d9a05b', '#6f9df0', '#72c39a', '#5fc2c9',
  '#b489e6', '#e08aa0', '#6270c9', '#e3b341',
  '#7bd88f', '#ff8fab', '#a78bfa', '#f0876a'
];

const baseRenderAll = renderAll;
const baseRenderChrome = renderChrome;
const baseSetVariant = setVariant;
const baseApplySelection = applySelection;
const baseUndo = undo;

const efDom = {
  viewBar: $('#viewBar'),
  viewNote: $('#viewNote'),
  densitySeg: $('#densitySeg'),
  collapseAll: $('#collapseAll'),
  tracksBtn: $('#tracksBtn'),
  editBtn: $('#editBtn'),
  appbar: $('#appbar'),
  abTitle: $('#abTitle'),
  abSub: $('#abSub'),
  modalRoot: $('#modalRoot')
};
const efBodyWrap = document.querySelector('.bodywrap');

if (!dom.tplBtn) dom.tplBtn = document.getElementById('tplBtn');

state.density = state.density || 'normal';
state.trackOpen = state.trackOpen || {};
state.resizingId = null;
state.efModal = null;
state.efTrackPop = false;
state.efPaletteFor = null;
state.efConfirmDel = null;

for (const t of TRACKS) {
  if (!(t.id in state.trackOpen)) state.trackOpen[t.id] = true;
}

function efIs() {
  return state.variant === 'E' || state.variant === 'F';
}

/* ---------- category plumbing ---------- */
function efSyncTrackById() {
  for (const k of Object.keys(TRACK_BY_ID)) delete TRACK_BY_ID[k];
  for (const t of TRACKS) TRACK_BY_ID[t.id] = t;
}

function efTrackId(block) {
  if (block.track === 'uncat') return 'uncat';
  return TRACKS.some(t => t.id === block.track) ? block.track : 'uncat';
}

function efEnsureUncat() {
  const need = blocks.some(b => efTrackId(b) === 'uncat');
  const idx = TRACKS.findIndex(t => t.id === 'uncat');
  if (need && idx < 0) {
    TRACKS.push({ ...EF_UNCAT });
    state.trackOpen.uncat = true;
  } else if (!need && idx >= 0) {
    TRACKS.splice(idx, 1);
    delete state.trackOpen.uncat;
  }
}

function efCountFor(id) {
  return blocks.filter(b => efTrackId(b) === id).length;
}

/* ---------- segments, lanes, selection reflow ---------- */
let EF_SEG = [];
let EF_MAX = {};
let EF_SEL = null;
let efSegSeq = 1;

const EF_EXTRA_NORMAL = 28;
const EF_EXTRA_COMPACT = 22;
const EF_COLLAPSED_H = 28;

function efExtra() {
  return state.density === 'compact' ? EF_EXTRA_COMPACT : EF_EXTRA_NORMAL;
}

function efRebuild() {
  EF_SEG = [];
  EF_MAX = {};
  EF_SEL = null;

  for (const b of blocks) {
    const tid = efTrackId(b);
    let s = b.start;
    while (s < b.end) {
      const day = startOfDay(s);
      const e = Math.min(b.end, day + DAY);
      if (e <= s) break;
      EF_SEG.push({
        id: efSegSeq++, block: b, tid, start: s, end: e, day,
        zone: b.type === 'zone', lane: 0
      });
      s = e;
    }
  }

  const groups = new Map();
  for (const sg of EF_SEG) {
    const k = sg.tid + '|' + sg.day + '|' + (sg.zone ? 'z' : 'e');
    if (!groups.has(k)) groups.set(k, []);
    groups.get(k).push(sg);
  }
  for (const arr of groups.values()) {
    arr.sort((a, b) => a.start - b.start || a.end - b.end);
    const ends = [];
    for (const sg of arr) {
      let lane = 0;
      while (lane < ends.length && ends[lane] > sg.start) lane++;
      ends[lane] = sg.end;
      sg.lane = lane;
    }
  }

  for (const sg of EF_SEG) {
    const m = EF_MAX[sg.tid] || (EF_MAX[sg.tid] = { z: 0, e: 0 });
    if (sg.zone) m.z = Math.max(m.z, sg.lane + 1);
    else m.e = Math.max(m.e, sg.lane + 1);
  }

  if (state.variant === 'F' && state.selectedId != null) {
    const b = blocks.find(x => x.id === state.selectedId);
    if (b && b.end - b.start < DAY) {
      const sg = EF_SEG.find(x => x.block.id === b.id);
      if (sg) {
        EF_SEL = { block: b, tid: sg.tid, lane: sg.lane, zone: sg.zone, day: sg.day };
      }
    }
  }
}

function efSelFor(tid) {
  return EF_SEL && EF_SEL.tid === tid ? EF_SEL : null;
}

function efMetrics(tid) {
  const open = state.trackOpen[tid] !== false;
  if (!open) return { h: EF_COLLAPSED_H, z: 0, e: 0, collapsed: true };

  const m = EF_MAX[tid] || { z: 0, e: 0 };
  const z = m.z;
  const e = Math.max(1, m.e);
  const compact = state.density === 'compact';

  let h = compact
    ? 6 + z * 12 + (z ? 4 : 0) + e * 24 + 4
    : 8 + z * 18 + (z ? 6 : 0) + e * 42;

  if (state.variant === 'F' && efSelFor(tid)) h += efExtra();
  return { h, z, e, collapsed: false };
}

function efLaneY(tid, lane, zone) {
  const compact = state.density === 'compact';
  const zPitch = compact ? 12 : 18;
  const ePitch = compact ? 24 : 42;
  const top = compact ? 6 : 8;

  if (zone) {
    let off = 0;
    if (EF_SEL && EF_SEL.tid === tid && EF_SEL.zone && lane > EF_SEL.lane) off = efExtra();
    return top + lane * zPitch + off;
  }

  const z = (EF_MAX[tid] || {}).z || 0;
  const y = top + z * zPitch + (z ? (compact ? 4 : 6) : 0);

  let off = 0;
  if (EF_SEL && EF_SEL.tid === tid) {
    if (EF_SEL.zone) off = efExtra();
    else if (lane > EF_SEL.lane) off = efExtra();
  }
  return y + lane * ePitch + off;
}

/* ---------- render ---------- */
function efRenderAll() {
  efRebuild();
  efEnsureUncat();
  efSyncTrackById();

  dom.device.dataset.variant = state.variant;
  dom.device.dataset.density = state.density;

  const w = dom.canvas.clientWidth;
  if (!w) return;
  PX = w / state.hours;

  efRenderGutter();
  renderRuler(w);
  renderBg(w);
  efRenderRows(w);
  efSizeTracks();
  renderPastNow(w);
  efRenderMinimap();
  efRenderChrome();
}

function efSizeTracks() {
  const total = TRACKS.reduce((n, t) => n + efMetrics(t.id).h, 0);
  const body = dom.canvas.parentElement;
  const h = Math.max(1, total, body.clientHeight);
  dom.canvas.style.height = h + 'px';
  dom.gutterCol.style.height = h + 'px';
  dom.rows.style.height = h + 'px';

  // The body scrolls vertically; reserve the same strip on the ruler and
  // minimap so their horizontal time scale stays aligned with the canvas.
  const sbw = Math.max(0, efBodyWrap.offsetWidth - efBodyWrap.clientWidth);
  dom.ruler.style.marginRight = sbw + 'px';
  dom.minimap.style.marginRight = sbw + 'px';
}

function efRenderGutter() {
  dom.gutterCol.innerHTML = '';
  for (const t of TRACKS) {
    const m = efMetrics(t.id);
    const open = state.trackOpen[t.id] !== false;
    const d = el('div', 'track-label' + (open ? '' : ' collapsed'));
    d.style.height = m.h + 'px';
    d.style.setProperty('--c', t.color);
    d.dataset.track = t.id;

    d.appendChild(el('span', 'dot'));
    d.appendChild(el('span', 'nm', t.name || 'Untitled'));

    const toggle = () => {
      state.trackOpen[t.id] = !open;
      renderAll();
    };
    d.title = 'Click to ' + (open ? 'collapse ' : 'expand ') + (t.name || 'track');
    d.addEventListener('click', toggle);

    const chev = el('button', 'chev', open ? '▾' : '▸');
    chev.type = 'button';
    chev.title = (open ? 'Collapse ' : 'Expand ') + (t.name || 'track');
    chev.dataset.chev = t.id;
    chev.addEventListener('click', e => {
      e.stopPropagation();
      toggle();
    });
    d.appendChild(chev);
    dom.gutterCol.appendChild(d);
  }
}

function efRenderRows(w) {
  dom.rows.innerHTML = '';
  const winStart = state.viewStart - HOUR;
  const winEnd = state.viewStart + state.hours * HOUR + HOUR;

  for (const t of TRACKS) {
    const m = efMetrics(t.id);
    const row = el('div', 'row' + (m.collapsed ? ' collapsed' : ''));
    row.style.height = m.h + 'px';
    row.style.setProperty('--c', t.color);
    row.dataset.track = t.id;

    if (!blocks.some(b => efTrackId(b) === t.id)) {
      row.appendChild(el('div', 'emptyhint', 'empty category'));
    }

    for (const sg of EF_SEG) {
      if (sg.tid !== t.id) continue;
      if (sg.end <= winStart || sg.start >= winEnd) continue;
      row.appendChild(efMakeBlock(sg, w, m));
    }
    dom.rows.appendChild(row);
  }
}

function efMakeBlock(sg, w, metrics) {
  const b = sg.block;
  const tid = sg.tid;
  const track = TRACK_BY_ID[tid] || EF_UNCAT;
  const open = state.trackOpen[tid] !== false;
  const compact = state.density === 'compact';
  const isZone = !!sg.zone;
  const isSel = b.id === state.selectedId;

  const x1 = xOf(sg.start, w);
  const x2 = xOf(sg.end, w);
  const width = Math.max(2, x2 - x1);

  const n = el('div', 'blk');
  n.dataset.id = b.id;
  if (isZone) n.classList.add('zone');
  if (width < 64) n.classList.add('narrow');
  if (width < (isZone ? 46 : 30)) n.classList.add('tiny');
  if (NOW >= sg.start && NOW < sg.end) n.classList.add('active');
  if (isSel) n.classList.add('sel');
  if (state.draggingId === b.id || state.resizingId === b.id) n.classList.add('grabbed');

  n.style.left = x1 + 'px';
  n.style.width = width + 'px';
  n.style.setProperty('--c', track.color);

  const fullInfo = b.title + ' · ' + fmtTime(b.start) + '–' + fmtTime(b.end) + ' · ' + track.name;
  n.title = fullInfo;

  if (!open) {
    const h = isZone ? 4 : 6;
    n.classList.add('ef-strip');
    n.style.top = ((EF_COLLAPSED_H - h) / 2) + 'px';
    n.style.height = h + 'px';
    n.style.background = isZone ? hexA(track.color, .52) : hexA(track.color, .9);
    n.style.borderColor = hexA(track.color, .7);
    if (isSel) n.classList.add('sel');
    efAddHandles(n, isSel);
    return n;
  }

  if (compact) n.classList.add('ef-compact');

  let h = isZone ? (compact ? 7 : 16) : (compact ? 18 : 34);
  const selExtra = (isSel && state.variant === 'F' && efSelFor(tid)) ? efExtra() : 0;
  if (selExtra) n.classList.add('f-expanded');
  h += selExtra;

  n.style.top = efLaneY(tid, sg.lane, isZone) + 'px';
  n.style.height = h + 'px';
  n.style.setProperty('--b1', hexA(track.color, isZone ? (compact ? .18 : .14) : (compact ? .30 : .34)));
  n.style.setProperty('--b2', hexA(track.color, isZone ? (compact ? .12 : .10) : (compact ? .18 : .20)));
  n.style.setProperty('--bd', hexA(track.color, isZone ? (compact ? .28 : .30) : (compact ? .42 : .45)));

  const showText = !compact || (state.variant === 'F' && isSel && selExtra > 0);
  if (showText) {
    const inner = el('div', 'inner');
    inner.style.left = Math.max(0, -x1) + 'px';
    inner.style.right = '0';
    inner.appendChild(el('div', 't', b.title));
    if (!isZone) inner.appendChild(el('div', 'm', blockMeta(b)));
    if (state.variant === 'F' && isSel && selExtra > 0) {
      inner.appendChild(el('div', 'detail', fmtTime(b.start) + '–' + fmtTime(b.end) + ' · ' + track.name));
    }
    n.appendChild(inner);
  }

  efAddHandles(n, isSel);
  return n;
}

function efAddHandles(node, isSel) {
  if (!isSel) return;
  const l = el('div', 'rs rs-l');
  const r = el('div', 'rs rs-r');
  l.title = 'Drag to change start';
  r.title = 'Drag to change end';
  node.appendChild(l);
  node.appendChild(r);
}

function efRenderMinimap() {
  const mm = dom.minimap;
  const w = mm.clientWidth;
  const h = mm.clientHeight;
  if (!w) return;
  mm.innerHTML = '';

  const from = TIMELINE_START;
  const to = TIMELINE_END;
  const mx = ts => (ts - from) / (to - from) * w;

  for (let d = startOfDay(from); d < to; d += DAY) {
    const dow = new Date(d).getDay();
    if (dow === 0 || dow === 6) {
      const band = el('div', 'mm-band');
      band.style.left = mx(d) + 'px';
      band.style.width = (w / TIMELINE_DAYS) + 'px';
      mm.appendChild(band);
    }
    const tick = el('div', 'mm-day');
    tick.style.left = mx(d) + 'px';
    mm.appendChild(tick);
  }

  const count = Math.max(1, TRACKS.length);
  const top0 = 5;
  const rowH = Math.max(1.4, Math.min(3.4, (h - 10 - (count - 1) * .7) / count));
  const gap = .7;

  TRACKS.forEach((t, i) => {
    for (const b of blocks) {
      if (efTrackId(b) !== t.id) continue;
      const a = mx(b.start);
      const c = mx(b.end);
      if (c < 0 || a > w) continue;
      const x = Math.max(0, a);
      const bw = Math.min(w, c) - x;
      if (bw < 0.6) continue;
      const k = el('div', 'mm-blk');
      k.style.left = x + 'px';
      k.style.width = Math.max(1, bw) + 'px';
      k.style.top = (top0 + i * (rowH + gap)) + 'px';
      k.style.height = rowH + 'px';
      k.style.background = t.color;
      mm.appendChild(k);
    }
  });

  const nowTick = el('div', 'mm-now');
  nowTick.style.left = mx(NOW) + 'px';
  mm.appendChild(nowTick);

  const vx = clamp(mx(state.viewStart), 0, w);
  const vx2 = clamp(mx(state.viewStart + state.hours * HOUR), 0, w);
  const view = el('div', 'mm-view');
  view.style.left = vx + 'px';
  view.style.width = Math.max(4, vx2 - vx) + 'px';
  mm.appendChild(view);
}

function efRenderChrome() {
  dom.sbTime.textContent = fmtTime(NOW);
  dom.zoomLabel.textContent = zoomName(state.hours);
  dom.undoBtn.classList.toggle('off', state.undo.length === 0);
  dom.lockBtn.textContent = state.locked ? '🔒' : '🔓';
  dom.device.classList.toggle('locked', state.locked);
  dom.device.dataset.variant = state.variant;
  dom.device.dataset.density = state.density;
  efDom.viewBar.hidden = false;

  const sel = state.selectedId != null ? blocks.find(b => b.id === state.selectedId) : null;

  if (sel) {
    const tid = efTrackId(sel);
    const t = TRACK_BY_ID[tid] || EF_UNCAT;
    const range = fmtTime(sel.start) + '–' + fmtTime(sel.end);
    const meta = blockMeta(sel);

    efDom.abTitle.innerHTML =
      '<span class="tdot" style="background:' + t.color + '"></span>' +
      '<span class="ttl">' + esc(sel.title) + '</span>' +
      '<span class="catchip" style="color:' + t.color +
        ';border-color:' + hexA(t.color, .36) +
        ';background:' + hexA(t.color, .12) + '">' + esc(t.name) + '</span>';

    let sub;
    if (state.variant === 'E') {
      sub = range + ' · ' + meta;
    } else {
      const collapsed = state.trackOpen[tid] === false;
      const multiDay = sel.end - sel.start >= DAY;
      const zone = sel.type === 'zone';
      sub = (collapsed || multiDay || zone) ? range + ' · ' + meta : range;
    }
    efDom.abSub.textContent = sub;
    efDom.abSub.title = sub;
    efDom.editBtn.hidden = false;
    efDom.appbar.classList.add('has-sel');
  } else {
    efDom.abTitle.textContent = 'Timeline';
    efDom.abSub.textContent = fmtDayLong(NOW);
    efDom.abSub.title = '';
    efDom.editBtn.hidden = true;
    efDom.appbar.classList.remove('has-sel');
  }

  efSyncViewbar();
}

function efSyncViewbar() {
  const total = TRACKS.length;
  const open = TRACKS.filter(t => state.trackOpen[t.id] !== false).length;
  const allClosed = total > 0 && open === 0;

  efDom.viewNote.textContent = allClosed
    ? 'all tracks collapsed'
    : (open === total ? (total + (total === 1 ? ' track open' : ' tracks open')) : (open + ' of ' + total + ' open'));

  efDom.collapseAll.textContent = allClosed ? 'Expand all' : 'Collapse all';
  efDom.tracksBtn.hidden = !(state.variant === 'F' && state.density === 'compact' && total > 1);

  for (const btn of efDom.densitySeg.querySelectorAll('button')) {
    btn.classList.toggle('on', btn.dataset.density === state.density);
  }
}

/* ---------- overrides ---------- */
renderAll = function () {
  if (efIs()) efRenderAll();
  else baseRenderAll();
};

renderChrome = function () {
  if (efIs()) efRenderChrome();
  else baseRenderChrome();
};

applySelection = function () {
  if (efIs()) renderAll();
  else baseApplySelection();
};

undo = function () {
  baseUndo();
  if (efIs()) {
    efEnsureUncat();
    efSyncTrackById();
    renderAll();
    if (state.efModal === 'cat') efRenderCategorySheet();
  }
};

setVariant = function (v) {
  if (v === 'E' || v === 'F') {
    state.variant = v;
    state.selectedId = null;
    closeEFSheets();
    closeEFTrackPop();
    document.querySelectorAll('.tab').forEach(b => b.classList.toggle('on', b.dataset.variant === v));
    dom.device.dataset.variant = v;
    dom.device.dataset.density = state.density;
    dom.deviceWrap.hidden = false;
    dom.trayScene.hidden = true;
    document.querySelectorAll('#deviceSeg button').forEach(b => { b.disabled = false; });
    efDom.viewBar.hidden = false;
    efDom.editBtn.hidden = true;
    efDom.appbar.classList.remove('has-sel');
    dom.tplBtn.textContent = 'Categories';
    dom.notes.innerHTML = NOTES[v];
    dom.hint.textContent = HINTS[v];
    efBodyWrap.scrollTop = 0;
    fitDevice();
    fitTray();
    requestAnimationFrame(renderAll);
  } else {
    state.variant = v;
    state.selectedId = null;
    closeEFSheets();
    closeEFTrackPop();
    efDom.viewBar.hidden = true;
    efDom.editBtn.hidden = true;
    efDom.abTitle.textContent = 'Timeline';
    efDom.appbar.classList.remove('has-sel');
    dom.tplBtn.textContent = 'Templates';
    dom.device.removeAttribute('data-density');
    dom.canvas.style.height = '';
    dom.gutterCol.style.height = '';
    dom.rows.style.height = '';
    dom.ruler.style.marginRight = '';
    dom.minimap.style.marginRight = '';
    efBodyWrap.scrollTop = 0;
    baseSetVariant(v);
    efDom.viewBar.hidden = true;
  }
};

/* ---------- selection / resize interaction ---------- */
let efResize = null;

dom.canvas.addEventListener('pointerdown', e => {
  if (!efIs()) return;
  const handle = e.target.closest ? e.target.closest('.rs') : null;
  if (!handle) return;

  e.preventDefault();
  e.stopPropagation();

  if (state.locked) {
    toast('Layout is locked — unlock to resize blocks');
    return;
  }

  const node = handle.closest('.blk');
  if (!node) return;
  const block = blocks.find(b => b.id === +node.dataset.id);
  if (!block) return;

  state.selectedId = block.id;
  state.resizingId = block.id;
  efResize = {
    block,
    side: handle.classList.contains('rs-l') ? 'l' : 'r',
    x0: e.clientX,
    start0: block.start,
    end0: block.end,
    snapshot: blocks.map(b => ({ ...b })),
    moved: false
  };
  renderAll();

  window.addEventListener('pointermove', efResizeMove);
  window.addEventListener('pointerup', efResizeEnd);
  window.addEventListener('pointercancel', efResizeEnd);
}, true);

function efResizeMove(e) {
  if (!efResize) return;
  const dx = e.clientX - efResize.x0;
  if (Math.abs(dx) > 1) efResize.moved = true;

  const snap = state.hours >= 72 ? 30 : state.hours >= 24 ? 15 : 5;
  const step = snap * 60000;
  const delta = Math.round(dx / PX * HOUR / step) * step;
  const b = efResize.block;

  if (efResize.side === 'l') {
    b.start = Math.min(efResize.start0 + delta, b.end - 60000);
  } else {
    b.end = Math.max(efResize.end0 + delta, b.start + 60000);
  }
  renderAll();
}

function efResizeEnd() {
  if (!efResize) return;
  window.removeEventListener('pointermove', efResizeMove);
  window.removeEventListener('pointerup', efResizeEnd);
  window.removeEventListener('pointercancel', efResizeEnd);

  const r = efResize;
  efResize = null;
  state.resizingId = null;

  if (r.moved) {
    pushUndo(r.snapshot, 'Resized ' + r.block.title);
    toast('Resized ' + r.block.title + ' · ' + fmtTime(r.block.start) + '–' + fmtTime(r.block.end), true);
  }
  renderAll();
}

/* ---------- wheel: zoom, horizontal pan, vertical track scroll ---------- */
efBodyWrap.addEventListener('wheel', e => {
  if (!efIs()) return;
  e.preventDefault();
  e.stopPropagation();

  if (e.ctrlKey) {
    const r = dom.canvas.getBoundingClientRect();
    const ratio = clamp((e.clientX - r.left) / r.width, 0, 1);
    zoomBy(e.deltaY > 0 ? 1.25 : .8, ratio);
    return;
  }

  const horizontal = e.shiftKey || Math.abs(e.deltaX) > Math.abs(e.deltaY);
  if (horizontal) {
    const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
    state.viewStart += d / PX * HOUR;
    clampView();
    renderAll();
    return;
  }

  if (efBodyWrap.scrollHeight > efBodyWrap.clientHeight + 1) {
    efBodyWrap.scrollTop = clamp(efBodyWrap.scrollTop + e.deltaY, 0, efBodyWrap.scrollHeight - efBodyWrap.clientHeight);
  } else {
    state.viewStart += e.deltaY / PX * HOUR;
    clampView();
    renderAll();
  }
}, { capture: true, passive: false });

/* ---------- view controls ---------- */
efDom.densitySeg.addEventListener('click', e => {
  const btn = e.target.closest('button[data-density]');
  if (!btn || !efIs()) return;
  if (state.density === btn.dataset.density) return;
  state.density = btn.dataset.density;
  closeEFTrackPop();
  renderAll();
});

efDom.collapseAll.addEventListener('click', () => {
  if (!efIs()) return;
  if (state.variant === 'G') {
    for (const t of TRACKS) state.trackOpen[t.id] = false;
    closeEFTrackPop();
    renderAll();
    return;
  }
  const allClosed = TRACKS.length > 0 && TRACKS.every(t => state.trackOpen[t.id] === false);
  for (const t of TRACKS) state.trackOpen[t.id] = allClosed;
  closeEFTrackPop();
  renderAll();
});

dom.canvas.addEventListener('dblclick', e => {
  if (!efIs()) return;
  const node = e.target.closest ? e.target.closest('.blk') : null;
  if (!node) return;
  if (state.selectedId !== +node.dataset.id) {
    state.selectedId = +node.dataset.id;
    renderAll();
  }
  if (typeof openEFEditor === 'function') openEFEditor();
});

/* ---------- notes ---------- */
NOTES.E = `<h3>Variant E</h3><h2>Header first — nothing moves</h2>
  <p>My interpretation. The timeline itself stays perfectly still. Tap a block and its details move into the <b>top bar</b>; the rows never change height.</p>
  <p><b>The key difference:</b> in F, selecting a bar makes its row taller, so every row below slides down. E avoids that by putting the information in the header.</p>
  <ul>
    <li><b>Normal / Compact</b> is one global switch. Normal shows the name and time inside bars. Compact hides that text and keeps a thin colour edge, so you see more at once.</li>
    <li><b>Open / closed per track</b> is a second, independent switch. Click a track's name or chevron: the row shrinks to a slim strip and the rows below move up <i>once</i> — because you asked for that.</li>
    <li><b>Tap</b> selects. <b>Hold + drag</b> moves. Drag the two pale <b>edge anchors</b> to resize. <b>✎</b> opens exact numeric times.</li>
    <li><b>Categories</b> (bottom bar) can be renamed, recoloured, added or deleted. Delete a category and its blocks move to <b>Uncategorized</b>. Zero categories is allowed.</li>
  </ul>
  <p><b>Many categories?</b> The track area scrolls vertically; the ruler and minimap stay put. Wheel scrolls tracks, shift+wheel moves time, ctrl+wheel zooms.</p>
  <p><b>Trade-off:</b> only one selected block can show detail at a time, and the top bar has limited room for a long name plus all the numbers.</p>
  <hr>
  <p><b>Try it:</b> select <b>Admin</b> and watch the rows stay put. Switch to Compact. Collapse Food with its chevron. Open Categories and delete Media.</p>`;

NOTES.F = `<h3>Variant F</h3><h2>Expand in place — your version</h2>
  <p>Your interpretation, taken literally. Tap a block and the block itself grows to reveal the “running / left” information. Its row gets taller, so everything below moves down.</p>
  <p><b>Point 1 in one sentence:</b> select <b>Admin</b> and watch Personal, Learning, Health, Media and Rest slide down by about 28px; deselect and they snap back. That is the jump I meant. It is not random — it only happens when you select — but it moves the thing you were looking at.</p>
  <ul>
    <li><b>Normal</b> is A, plus the selected block expands in place with the extra line.</li>
    <li><b>Compact</b> removes the category column. Tracks are identified by a <b>3px colour rail</b> at the left edge; tap a block to see its category in the header. Use <b>Tracks</b> in the view bar to open/collapse tracks while the names are hidden.</li>
    <li>Per-track names/chevrons work in Normal. The open/closed state is kept when you switch to Compact.</li>
    <li>Tap selects, hold+drag moves, the edge anchors resize, ✎ opens exact times. Categories work exactly as in E.</li>
  </ul>
  <p><b>Many categories?</b> The track area scrolls vertically; the ruler and minimap stay put. Wheel scrolls tracks, shift+wheel moves time, ctrl+wheel zooms.</p>
  <hr>
  <p><b>Try it:</b> select Admin, then click empty space to deselect and watch the rows move back. Switch to Compact to lose the category column. Collapse a track. Open Categories and delete Media.</p>`;

HINTS.E = 'tap to select · hold to move · edge anchors resize · ✎ exact times · chevrons collapse tracks';
HINTS.F = 'tap to expand in place · hold to move · edge anchors resize · ✎ exact times';

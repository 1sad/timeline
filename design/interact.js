/* ---------- helpers ---------- */
let drag = null;

function markGrabbed(on, id) {
  document.querySelectorAll('.blk.grabbed').forEach(n => n.classList.remove('grabbed'));
  if (on && id != null) {
    const n = dom.rows.querySelector('.blk[data-id="' + id + '"]');
    if (n) n.classList.add('grabbed');
  }
}

function applySelection() {
  document.querySelectorAll('.blk.sel').forEach(n => n.classList.remove('sel'));
  if (state.selectedId != null) {
    const n = dom.rows.querySelector('.blk[data-id="' + state.selectedId + '"]');
    if (n) n.classList.add('sel');
  }
  renderChrome();
}

let toastTimer = null;
function toast(msg, withUndo) {
  dom.toast.innerHTML = '';
  dom.toast.appendChild(el('span', '', msg));
  if (withUndo) {
    const b = el('button', '', 'Undo');
    b.onclick = () => { undo(); dom.toast.classList.remove('show'); };
    dom.toast.appendChild(b);
  }
  dom.toast.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => dom.toast.classList.remove('show'), withUndo ? 5200 : 2400);
}

function pushUndo(snapshot, label) {
  state.undo.push({ snapshot, label });
  if (state.undo.length > 25) state.undo.shift();
  renderChrome();
}

function undo() {
  const a = state.undo.pop();
  if (!a) { toast('Nothing to undo'); return; }
  blocks.length = 0;
  for (const b of a.snapshot) blocks.push({ ...b });
  if (a.tracks) {
    TRACKS.length = 0;
    for (const t of a.tracks) TRACKS.push({ ...t });
  }
  if (a.trackOpen) state.trackOpen = { ...a.trackOpen };
  state.selectedId = null;
  renderAll();
  toast('Undid: ' + a.label);
}

/* ---------- canvas pointer ---------- */
dom.canvas.addEventListener('pointerdown', e => {
  if (e.pointerType === 'mouse' && e.button !== 0) return;

  const node = e.target.closest('.blk');
  const block = node ? blocks.find(b => b.id === +node.dataset.id) : null;
  if (block) {
    state.selectedId = block.id;
    applySelection();
  }

  if (!block) {
    drag = {
      mode: 'pan', x0: e.clientX, y0: e.clientY,
      view0: state.viewStart, scroll0: dom.canvas.parentElement.scrollTop,
      moved: false, empty: true, axis: null
    };
    dom.canvas.setPointerCapture(e.pointerId);
    return;
  }

  if (state.locked) {
    toast('Layout is locked — unlock to move blocks');
    renderChrome();
    return;
  }

  drag = {
    mode: 'pending',
    x0: e.clientX,
    block,
    t0: block.start,
    dur: block.end - block.start,
    snapshot: blocks.map(b => ({ ...b })),
    pointerType: e.pointerType || 'mouse',
    moved: false,
    empty: false,
  };
  dom.canvas.setPointerCapture(e.pointerId);

  if (e.pointerType !== 'mouse') {
    drag.timer = setTimeout(() => {
      if (!drag || drag.mode !== 'pending' || !drag.block) return;
      drag.mode = 'block';
      state.draggingId = drag.block.id;
      markGrabbed(true, drag.block.id);
      if (navigator.vibrate) navigator.vibrate(12);
    }, 300);
  }
});

dom.canvas.addEventListener('pointermove', e => {
  if (!drag) return;
  const dx = e.clientX - drag.x0;
  const dy = e.clientY - (drag.y0 != null ? drag.y0 : e.clientY);

  // E/F: when many tracks overflow, a vertical drag on empty space scrolls
  // the track list instead of panning time. Horizontal drags still pan.
  if (drag.mode === 'pan' && drag.empty) {
    const wrap = dom.canvas.parentElement;
    const canV = (state.variant === 'E' || state.variant === 'F' || state.variant === 'G') &&
      wrap.scrollHeight > wrap.clientHeight + 1;
    if (canV) {
      if (!drag.axis) {
        if (Math.abs(dx) < 4 && Math.abs(dy) < 4) return;
        drag.axis = Math.abs(dy) > Math.abs(dx) ? 'v' : 'h';
      }
      if (drag.axis === 'v') {
        if (Math.abs(dy) > 4) drag.moved = true;
        wrap.scrollTop = clamp(drag.scroll0 - dy, 0, wrap.scrollHeight - wrap.clientHeight);
        dom.canvas.classList.add('panning');
        return;
      }
    }
  }

  if (drag.mode === 'pending') {
    const threshold = drag.pointerType === 'mouse' ? 3 : 9;
    if (Math.abs(dx) <= threshold) return;
    if (drag.block) {
      drag.mode = 'block';
      state.draggingId = drag.block.id;
      markGrabbed(true, drag.block.id);
    } else {
      drag.mode = 'pan';
    }
  }

  if (drag.mode === 'pan') {
    if (Math.abs(dx) > 4) drag.moved = true;
    state.viewStart = drag.view0 - dx / PX * HOUR;
    clampView();
    dom.canvas.classList.add('panning');
    renderAll();
    return;
  }

  if (drag.mode === 'block') {
    drag.moved = true;
    const snap = state.hours >= 72 ? 30 : state.hours >= 24 ? 15 : 5;
    const raw = drag.t0 + dx / PX * HOUR;
    const snapped = Math.round(raw / (snap * 60000)) * (snap * 60000);
    drag.block.start = snapped;
    drag.block.end = snapped + drag.dur;
    renderAll();
    markGrabbed(true, drag.block.id);
  }
});

function endDrag(e) {
  if (!drag) return;
  clearTimeout(drag.timer);
  dom.canvas.classList.remove('panning');

  if (drag.mode === 'block' && drag.moved) {
    pushUndo(drag.snapshot, 'Moved ' + drag.block.title);
    toast('Moved ' + drag.block.title + ' · ' + fmtTime(drag.block.start) + '–' + fmtTime(drag.block.end), true);
  } else if (drag.empty && drag.mode === 'pan' && !drag.moved) {
    state.selectedId = null;
    renderAll();
  }

  state.draggingId = null;
  markGrabbed(false);
  drag = null;
  renderChrome();
}
dom.canvas.addEventListener('pointerup', endDrag);
dom.canvas.addEventListener('pointercancel', endDrag);

/* ---------- wheel ---------- */
dom.canvas.addEventListener('wheel', e => {
  e.preventDefault();
  if (e.ctrlKey) {
    const r = dom.canvas.getBoundingClientRect();
    const ratio = clamp((e.clientX - r.left) / r.width, 0, 1);
    zoomBy(e.deltaY > 0 ? 1.25 : 0.8, ratio);
    return;
  }
  const d = Math.abs(e.deltaX) > Math.abs(e.deltaY) ? e.deltaX : e.deltaY;
  state.viewStart += d / PX * HOUR;
  clampView();
  renderAll();
}, { passive: false });

/* ---------- minimap ---------- */
let mmDrag = false;
function mmJump(e) {
  const r = dom.minimap.getBoundingClientRect();
  const ratio = clamp((e.clientX - r.left) / r.width, 0, 1);
  const t = TIMELINE_START + ratio * (TIMELINE_END - TIMELINE_START);
  state.viewStart = t - state.hours * 0.5 * HOUR;
  clampView();
  renderAll();
}
dom.minimap.addEventListener('pointerdown', e => {
  mmDrag = true;
  dom.minimap.setPointerCapture(e.pointerId);
  mmJump(e);
});
dom.minimap.addEventListener('pointermove', e => { if (mmDrag) mmJump(e); });
dom.minimap.addEventListener('pointerup', () => { mmDrag = false; });
dom.minimap.addEventListener('pointercancel', () => { mmDrag = false; });

/* ---------- controls ---------- */
document.querySelectorAll('.tab').forEach(t => {
  t.addEventListener('click', () => setVariant(t.dataset.variant));
});

document.querySelectorAll('#deviceSeg button').forEach(b => {
  b.addEventListener('click', () => {
    if (!b.disabled) setDevice(b.dataset.device);
  });
});

dom.undoBtn.addEventListener('click', undo);

dom.lockBtn.addEventListener('click', () => {
  state.locked = !state.locked;
  renderChrome();
  toast(state.locked ? 'Layout locked — blocks cannot be moved' : 'Layout unlocked');
});

document.getElementById('nowBtn').addEventListener('click', () => {
  state.selectedId = null;
  goNow();
});

document.getElementById('zoomIn').addEventListener('click', () => zoomStep(-1));
document.getElementById('zoomOut').addEventListener('click', () => zoomStep(1));

document.getElementById('addBtn').addEventListener('click', () => {
  toast('New block — opens a quick create sheet in the real app');
});

document.getElementById('tplBtn').addEventListener('click', () => {
  toast('Templates — saved presets you stamp onto the timeline');
});

/* ---------- keyboard ---------- */
window.addEventListener('keydown', e => {
  if (e.key === 'n' || e.key === 'N') { state.selectedId = null; goNow(); }
  if (e.key === 'Escape') { state.selectedId = null; renderAll(); }
  if ((e.ctrlKey || e.metaKey) && e.key.toLowerCase() === 'z') { e.preventDefault(); undo(); }
  if (e.key === '+' || e.key === '=') { e.preventDefault(); zoomStep(-1); }
  if (e.key === '-') { e.preventDefault(); zoomStep(1); }
});

/* ---------- init ---------- */
dom.device.dataset.variant = state.variant;
dom.notes.innerHTML = NOTES.A + TRY_TEXT;
dom.hint.textContent = HINTS.A;
document.getElementById('tpDate').textContent = fmtDayLong(NOW) + ' · ' + fmtTime(NOW);
document.getElementById('tbClock').textContent = fmtTime(NOW);

fitDevice();
requestAnimationFrame(renderAll);
window.addEventListener('resize', () => { fitDevice(); fitTray(); renderAll(); });

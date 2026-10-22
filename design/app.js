/* ---------- dom ---------- */
const $ = s => document.querySelector(s);
const dom = {
  stage: $('#stage'),
  deviceWrap: $('#deviceWrap'),
  device: $('#device'),
  trayScene: $('#trayScene'),
  canvas: $('#canvas'),
  rows: $('#rows'),
  bg: $('#bgLayer'),
  past: $('#pastLayer'),
  nowLayer: $('#nowLayer'),
  ruler: $('#ruler'),
  gutterCol: $('#gutterCol'),
  minimap: $('#minimap'),
  abSub: $('#abSub'),
  sbTime: $('#sbTime'),
  zoomLabel: $('#zoomLabel'),
  undoBtn: $('#undoBtn'),
  lockBtn: $('#lockBtn'),
  toast: $('#toast'),
  notes: $('#notes'),
  hint: $('#hint'),
};

const el = (tag, cls, text) => {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text != null) n.textContent = text;
  return n;
};

/* ---------- layout math ---------- */
let SEGMENTS = [];
let TRACK_MAX = {};
let PX = 8;
let segSeq = 1;

const xOf = (ts, w) => (ts - state.viewStart) / HOUR * (w / state.hours);

function rebuildSegments() {
  SEGMENTS = [];
  for (const b of blocks) {
    let s = b.start;
    while (s < b.end) {
      const day = startOfDay(s);
      const e = Math.min(b.end, day + DAY);
      if (e <= s) break;
      SEGMENTS.push({ id: segSeq++, block: b, start: s, end: e, day, zone: b.type === 'zone', lane: 0 });
      s = e;
    }
  }

  TRACK_MAX = {};
  const groups = new Map();
  for (const sg of SEGMENTS) {
    const k = state.variant === 'B'
      ? sg.block.track + '|' + sg.day + '|all'
      : sg.block.track + '|' + sg.day + '|' + (sg.zone ? 'z' : 'e');
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
      const m = TRACK_MAX[sg.block.track] || (TRACK_MAX[sg.block.track] = { z: 0, e: 0 });
      if (state.variant === 'B' || !sg.zone) m.e = Math.max(m.e, lane + 1);
      else m.z = Math.max(m.z, lane + 1);
    }
  }
}

function metrics(trackId) {
  const m = TRACK_MAX[trackId] || { z: 0, e: 0 };
  if (state.variant === 'B') {
    const n = Math.max(1, m.e);
    return { z: 0, e: n, h: 8 + n * 34 };
  }
  return {
    z: m.z,
    e: m.e,
    h: 8 + m.z * 18 + (m.z ? 6 : 0) + Math.max(m.e, 1) * 44,
  };
}

function laneY(trackId, lane, zone) {
  if (state.variant === 'B') return 8 + lane * 34;
  if (zone) return 8 + lane * 18;
  const m = metrics(trackId);
  return 8 + m.z * 18 + (m.z ? 6 : 0) + lane * 44;
}

function blockMeta(b) {
  const dur = b.end - b.start;
  if (NOW >= b.start && NOW < b.end) {
    return fmtDur(NOW - b.start) + ' in · ' + fmtDur(b.end - NOW) + ' left';
  }
  if (NOW < b.start) return 'in ' + fmtDur(b.start - NOW);
  return fmtDur(dur);
}

/* ---------- render ---------- */
function renderAll() {
  if (state.variant === 'D') return;
  rebuildSegments();
  const w = dom.canvas.clientWidth;
  if (!w) return;
  PX = w / state.hours;
  renderGutter();
  renderRuler(w);
  renderBg(w);
  renderRows(w);
  renderPastNow(w);
  renderMinimap();
  renderChrome();
}

function renderGutter() {
  dom.gutterCol.innerHTML = '';
  for (const t of TRACKS) {
    const m = metrics(t.id);
    const d = el('div', 'track-label');
    d.style.height = m.h + 'px';
    d.style.setProperty('--c', t.color);
    d.appendChild(el('span', 'dot'));
    d.appendChild(el('span', 'nm', t.name));
    dom.gutterCol.appendChild(d);
  }
}

/* Ruler density is chosen from the visible window, not from a fixed
   hour step. Labels stay around 48-96px apart; the tick below them
   can be finer. This is what keeps 1h usable without turning 1d into
   a picket fence. */
function rulerSpec(hours) {
  const MIN = 60 * 1000;
  if (hours <= 1.5) return { label: 15 * MIN, minor: 5 * MIN, clock: true };
  if (hours <= 3.5) return { label: 30 * MIN, minor: 15 * MIN, clock: true };
  if (hours <= 7)   return { label: HOUR, minor: 15 * MIN, clock: false };
  if (hours <= 9)   return { label: HOUR, minor: 30 * MIN, clock: false };
  if (hours <= 15)  return { label: HOUR, minor: 30 * MIN, clock: false };
  if (hours <= 30)  return { label: 2 * HOUR, minor: HOUR, clock: false };
  if (hours <= 80)  return { label: 6 * HOUR, minor: 6 * HOUR, clock: false };
  return { label: DAY, minor: 12 * HOUR, clock: false, dayLabelsOnly: true };
}

function nextDayStart(ts) {
  const d = new Date(ts);
  d.setDate(d.getDate() + 1);
  d.setHours(0, 0, 0, 0);
  return d.getTime();
}

/* Build ticks from local calendar midnight instead of epoch offsets.
   That keeps 00/06/12/18 and the day boundaries aligned through DST,
   which is where the old 3d/8d ruler looked uneven. */
function localTicks(start, end, step) {
  const out = [];
  const stepMin = Math.round(step / 60000);
  if (stepMin <= 0 || stepMin > 24 * 60) return out;

  let day = startOfDay(start);
  while (day < end) {
    for (let m = 0; m < 24 * 60; m += stepMin) {
      const d = new Date(day);
      d.setHours(Math.floor(m / 60), m % 60, 0, 0);
      const t = d.getTime();
      if (t >= start && t < end) out.push(t);
    }
    day = nextDayStart(day);
  }
  return out;
}

function renderRuler(w) {
  dom.ruler.innerHTML = '';
  const start = state.viewStart;
  const end = start + state.hours * HOUR;
  const px = PX;
  const dayW = DAY / HOUR * px;
  const labelEvery = dayW >= 35 ? 1 : dayW >= 22 ? 2 : 4;
  const tightDays = dayW < 42;
  const spec = rulerSpec(state.hours);

  let di = 0;
  for (let d = startOfDay(start); d < end + DAY; d = nextDayStart(d), di++) {
    const x = xOf(d, w);
    if (x < -100 || x > w + 100) continue;
    const line = el('div', 'dayline');
    line.style.left = x + 'px';
    if (di % labelEvery === 0) {
      line.appendChild(el('span', tightDays ? 'tight' : '', tightDays ? fmtDayTight(d) : fmtDay(d)));
    }
    dom.ruler.appendChild(line);
  }

  const labelMin = Math.round(spec.label / 60000);
  for (const t of localTicks(start, end, spec.minor)) {
    const d = new Date(t);
    const minuteOfDay = d.getHours() * 60 + d.getMinutes();
    const m = d.getMinutes();
    let cls = 'hour';
    if (m === 0) cls += ' major';
    else if (m === 30) cls += ' half';
    else cls += ' minor';

    const labeled = !spec.dayLabelsOnly && minuteOfDay % labelMin === 0;
    if (labeled) cls += ' labeled';

    const tick = el('div', cls);
    tick.style.left = xOf(t, w) + 'px';
    if (labeled) {
      tick.appendChild(el('span', '', spec.clock ? pad2(d.getHours()) + ':' + pad2(m) : pad2(d.getHours())));
    }
    dom.ruler.appendChild(tick);
  }
}

function renderBg(w) {
  dom.bg.innerHTML = '';
  const start = state.viewStart;
  const end = start + state.hours * HOUR;

  for (let d = startOfDay(start); d < end + DAY; d += DAY) {
    const dow = new Date(d).getDay();
    if (dow === 0 || dow === 6) {
      const a = Math.max(0, xOf(d, w));
      const b = Math.min(w, xOf(d + DAY, w));
      if (b > a) {
        const band = el('div', 'band weekend');
        band.style.left = a + 'px';
        band.style.width = (b - a) + 'px';
        dom.bg.appendChild(band);
      }
    }
    for (const [from, to] of [[20, 31]]) {
      const a = Math.max(0, xOf(d + from * HOUR, w));
      const b = Math.min(w, xOf(d + to * HOUR, w));
      if (b > a) {
        const band = el('div', 'band night');
        band.style.left = a + 'px';
        band.style.width = (b - a) + 'px';
        dom.bg.appendChild(band);
      }
    }
  }

  const step = PX >= 40 ? 1 : PX >= 16 ? 2 : PX >= 6 ? 6 : 12;
  for (let t = Math.ceil(start / HOUR) * HOUR; t < end; t += HOUR) {
    const h = new Date(t).getHours();
    if (h % step !== 0) continue;
    const line = el('div', 'gridline' + (h % 6 === 0 ? ' major' : ''));
    line.style.left = xOf(t, w) + 'px';
    dom.bg.appendChild(line);
  }
}

function renderRows(w) {
  dom.rows.innerHTML = '';
  const winStart = state.viewStart - HOUR;
  const winEnd = state.viewStart + state.hours * HOUR + HOUR;

  for (const t of TRACKS) {
    const m = metrics(t.id);
    const row = el('div', 'row');
    row.style.height = m.h + 'px';

    if (state.variant === 'C') {
      const tag = el('div', 'rowtag', t.name);
      tag.style.setProperty('--c', t.color);
      row.appendChild(tag);
    }

    for (const sg of SEGMENTS) {
      if (sg.block.track !== t.id) continue;
      if (sg.end <= winStart || sg.start >= winEnd) continue;
      row.appendChild(makeBlockEl(sg, w));
    }
    dom.rows.appendChild(row);
  }
}

function makeBlockEl(sg, w) {
  const b = sg.block;
  const track = TRACK_BY_ID[b.track];
  const isZone = sg.zone && state.variant !== 'B';
  const x1 = xOf(sg.start, w);
  const x2 = xOf(sg.end, w);
  const width = Math.max(2, x2 - x1);

  const n = el('div', 'blk ' + (isZone ? 'zone' : 'event'));
  n.dataset.id = b.id;
  n.style.left = x1 + 'px';
  n.style.width = width + 'px';
  n.style.top = laneY(b.track, sg.lane, isZone) + 'px';
  n.style.height = (isZone ? 16 : state.variant === 'B' ? 26 : 36) + 'px';
  n.style.setProperty('--c', track.color);
  n.style.setProperty('--b1', hexA(track.color, isZone ? 0.14 : 0.34));
  n.style.setProperty('--b2', hexA(track.color, isZone ? 0.10 : 0.20));
  n.style.setProperty('--bd', hexA(track.color, isZone ? 0.30 : 0.45));

  if (width < 64) n.classList.add('narrow');
  if (width < (isZone ? 46 : 30)) n.classList.add('tiny');
  if (NOW >= sg.start && NOW < sg.end) n.classList.add('active');
  if (b.id === state.selectedId) n.classList.add('sel');
  if (state.draggingId === b.id) n.classList.add('grabbed');

  const inner = el('div', 'inner');
  inner.style.left = Math.max(0, -x1) + 'px';
  inner.style.right = '0';
  inner.appendChild(el('div', 't', b.title));
  inner.appendChild(el('div', 'm', blockMeta(b)));
  n.appendChild(inner);
  n.appendChild(el('div', 'grip'));

  if (b.type === 'zone' && state.variant === 'B') n.style.opacity = '0.72';
  return n;
}

function renderPastNow(w) {
  dom.past.innerHTML = '';
  dom.nowLayer.innerHTML = '';
  const nx = xOf(NOW, w);

  if (nx > 0) {
    const veil = el('div', 'pastveil');
    veil.style.width = Math.min(nx, w) + 'px';
    dom.past.appendChild(veil);
  }
  if (nx > -4 && nx < w + 4) {
    const line = el('div', 'nowline');
    line.style.left = nx + 'px';
    dom.nowLayer.appendChild(line);
    const pill = el('div', 'nowpill', 'now ' + fmtTime(NOW));
    pill.style.left = clamp(nx, 28, w - 28) + 'px';
    dom.nowLayer.appendChild(pill);
  }
}

function renderMinimap() {
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

  const rowH = 3.5;
  const gap = 1;
  const top0 = 5;
  TRACKS.forEach((t, i) => {
    for (const b of blocks) {
      if (b.track !== t.id) continue;
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

function renderChrome() {
  dom.sbTime.textContent = fmtTime(NOW);
  dom.zoomLabel.textContent = zoomName(state.hours);
  dom.undoBtn.classList.toggle('off', state.undo.length === 0);
  dom.lockBtn.textContent = state.locked ? '🔒' : '🔓';
  dom.device.classList.toggle('locked', state.locked);

  const sel = state.selectedId ? blocks.find(b => b.id === state.selectedId) : null;
  if (sel) {
    dom.abSub.textContent = sel.title + ' · ' + fmtTime(sel.start) + '–' + fmtTime(sel.end) + ' · ' + fmtDur(sel.end - sel.start);
  } else {
    dom.abSub.textContent = fmtDayLong(NOW);
  }
}

/* ---------- zoom ---------- */
const PRESETS = [1, 3, 6, 12, 24, 72, 192];
const zoomName = h => h < 24
  ? Math.round(h) + 'h'
  : h === 24 ? '1d'
  : h === 72 ? '3d'
  : h === 192 ? '8d'
  : Math.round(h / 24) + 'd';

function setHours(h, anchorRatio = 0.35) {
  h = clamp(h, 1, 192);
  const t = state.viewStart + state.hours * anchorRatio * HOUR;
  state.hours = h;
  state.viewStart = t - h * anchorRatio * HOUR;
  clampView();
  renderAll();
}

function zoomBy(f, anchor = 0.35) {
  setHours(clamp(state.hours * f, 1, 192), anchor);
}

function zoomStep(dir) {
  if (dir < 0) {
    const next = [...PRESETS].reverse().find(h => h < state.hours - 0.01);
    setHours(next != null ? next : PRESETS[0]);
  } else {
    const next = PRESETS.find(h => h > state.hours + 0.01);
    setHours(next != null ? next : PRESETS[PRESETS.length - 1]);
  }
}

function clampView() {
  const span = state.hours * HOUR;
  const maxStart = Math.max(TIMELINE_START, TIMELINE_END - span);
  state.viewStart = clamp(state.viewStart, TIMELINE_START, maxStart);
}

function goNow() {
  state.viewStart = NOW - state.hours * 0.3 * HOUR;
  clampView();
  renderAll();
}

/* ---------- notes ---------- */
const NOTES = {
  A: `<h3>Variant A</h3><h2>Two-tier timeline</h2>
    <p>Long things — digestion, sleep — are drawn as quiet <b>ribbons</b>. Short things stay as readable <b>bars</b> in front.</p>
    <ul>
      <li>Three 12h digestions get <b>three thin lanes</b>, so they stack instead of hiding each other.</li>
      <li>Every day is packed <b>independently</b>, so lanes never jump while you scroll.</li>
      <li>Track order is manual; in the real app you drag the labels.</li>
    </ul>
    <p><b>Trade-off:</b> zones take vertical space even when they are empty.</p>`,
  B: `<h3>Variant B</h3><h2>Everything fights for lanes</h2>
    <p>No special treatment: digestions, sleep and events all compete for the same lanes, like a classic calendar.</p>
    <ul>
      <li>See how the 12h windows push meals into random rows.</li>
      <li>Lane positions change from day to day, which makes scanning harder.</li>
      <li>Simple to build, but the timeline gets noisy fast.</li>
    </ul>
    <p><b>Trade-off:</b> honest but cluttered — this is the version your instinct warned you about.</p>`,
  C: `<h3>Variant C</h3><h2>Two-tier, full width</h2>
    <p>Same as A, but the track column is gone, so the phone gets ~13% more time width. Track names float as small tags.</p>
    <ul>
      <li>More room for labels at the same zoom.</li>
      <li>Names overlap the first blocks slightly.</li>
      <li>Best if you mostly rely on colour memory.</li>
    </ul>
    <p><b>Trade-off:</b> saves width, loses a stable anchor on the left.</p>`,
  D: `<h3>Variant D</h3><h2>Tray popup (Windows)</h2>
    <p>Left-click the tray icon: a compact card above the taskbar. Closing the main window keeps the app running here.</p>
    <ul>
      <li><b>Now</b> with a live progress bar.</li>
      <li>Next three things, one line each.</li>
      <li>Open the timeline or quick-add without switching windows.</li>
      <li>Notifications fire from this background process.</li>
    </ul>
    <p><b>Trade-off:</b> none really — it is the smallest useful window.</p>`,
};

const HINTS = {
  A: 'drag empty space to scroll · ctrl+wheel to zoom · hold a block on touch to grab it',
  B: 'drag empty space to scroll · ctrl+wheel to zoom · hold a block on touch to grab it',
  C: 'drag empty space to scroll · ctrl+wheel to zoom · hold a block on touch to grab it',
  D: 'the popup only exists while the app is running in the tray',
};

const TRY_TEXT = '<hr><p><b>Try it:</b> drag empty space to scroll, use − / + to zoom, drag a block, press Undo, then toggle the lock. On touch, hold a block for 0.3s before dragging.</p>';

/* ---------- device ---------- */
function fitDevice() {
  if (state.variant === 'D') return;
  const pad = 24;
  const aw = dom.stage.clientWidth - pad * 2;
  const ah = dom.stage.clientHeight - pad * 2;
  const dw = dom.device.offsetWidth;
  const dh = dom.device.offsetHeight;
  const s = Math.min(1, aw / dw, ah / dh);
  dom.device.style.transform = 'scale(' + s + ')';
  dom.deviceWrap.style.width = (dw * s) + 'px';
  dom.deviceWrap.style.height = (dh * s) + 'px';
}

function fitTray() {
  if (state.variant !== 'D') return;
  const pad = 24;
  const aw = dom.stage.clientWidth - pad * 2;
  const ah = dom.stage.clientHeight - pad * 2;
  const s = Math.min(1, aw / 1000, ah / 600);
  dom.trayScene.style.transform = 'scale(' + s + ')';
}

function setDevice(device) {
  state.device = device;
  dom.device.className = 'device ' + device + (state.locked ? ' locked' : '');
  dom.device.dataset.variant = state.variant;
  document.querySelectorAll('#deviceSeg button').forEach(b => b.classList.toggle('on', b.dataset.device === device));
  state.hours = device === 'phone' ? 8 : 24;
  state.viewStart = NOW - state.hours * 0.3 * HOUR;
  fitDevice();
  requestAnimationFrame(renderAll);
}

function setVariant(v) {
  state.variant = v;
  document.querySelectorAll('.tab').forEach(b => b.classList.toggle('on', b.dataset.variant === v));
  dom.device.dataset.variant = v;
  const tray = v === 'D';
  dom.deviceWrap.hidden = tray;
  dom.trayScene.hidden = !tray;
  document.querySelectorAll('#deviceSeg button').forEach(b => { b.disabled = tray; });
  dom.notes.innerHTML = (NOTES[v] || '') + (v === 'D'
    ? '<hr><p><b>Note:</b> the popup and the main window are the same process — closing the window only hides it.</p>'
    : TRY_TEXT);
  dom.hint.textContent = HINTS[v] || '';
  fitDevice();
  fitTray();
  if (!tray) requestAnimationFrame(renderAll);
}

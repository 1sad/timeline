/* ============================================================
   Variant G — the user's hybrid, streamlined.
   E header-first selection, no row movement, all tracks open by
   default. The whole second row is gone. Two icon buttons sit on the
   left of the bottom bar, the time-scale selector is centered, and a
   square-ish NEW is on the right. The Categories edit button lives
   at the foot of the name column, so it disappears with the names.
   The entire timeline is a finite eight days.
   ============================================================ */

const gExpandAll = document.getElementById('expandAll');
const gTracksBtn = document.getElementById('gTracksBtn');
const gCollapseBtn = document.getElementById('gCollapseBtn');
const gEditBtn = document.getElementById('gEditBtn');
const gBaseRenderAll = efRenderAll;
const gBaseRenderChrome = efRenderChrome;
const gBaseSyncViewbar = efSyncViewbar;
const gBaseSetVariant = setVariant;

state.gNamesHidden = state.gNamesHidden || false;
let gVisited = false;

/* G uses all of E's rendering. Only the header details, bottom
   controls and hidden name column need a G-specific branch. */
efIs = function () {
  return state.variant === 'E' || state.variant === 'F' || state.variant === 'G';
};

efRenderAll = function () {
  if (state.variant === 'G') {
    dom.device.dataset.names = state.gNamesHidden ? 'hidden' : 'shown';
  } else {
    delete dom.device.dataset.names;
  }
  gBaseRenderAll();
};

efRenderChrome = function () {
  gBaseRenderChrome();

  if (state.variant !== 'G') return;
  const sel = state.selectedId ? blocks.find(b => b.id === state.selectedId) : null;
  if (!sel) return;

  // G always shows the full range + running/left text, like E.
  const sub = fmtTime(sel.start) + '–' + fmtTime(sel.end) + ' · ' + blockMeta(sel);
  efDom.abSub.textContent = sub;
  efDom.abSub.title = sub;
};

efSyncViewbar = function () {
  if (state.variant !== 'G') {
    if (gTracksBtn) gTracksBtn.hidden = true;
    if (gCollapseBtn) gCollapseBtn.hidden = true;
    if (gEditBtn) gEditBtn.hidden = true;
    if (gExpandAll) gExpandAll.hidden = true;
    if (dom.tplBtn) dom.tplBtn.hidden = false;
    efDom.tracksBtn.classList.remove('on');
    efDom.tracksBtn.setAttribute('aria-pressed', 'false');
    efDom.tracksBtn.title = '';
    efDom.collapseAll.disabled = false;
    gBaseSyncViewbar();
    return;
  }

  // The old second row stays hidden; the bottom bar is the only
  // permanently visible set of view controls.
  efDom.viewBar.hidden = true;
  if (gExpandAll) gExpandAll.hidden = true;
  if (dom.tplBtn) dom.tplBtn.hidden = true;

  const total = TRACKS.length;
  const open = TRACKS.filter(t => state.trackOpen[t.id] !== false).length;
  const allClosed = total > 0 && open === 0;

  if (gTracksBtn) {
    gTracksBtn.hidden = false;
    gTracksBtn.classList.toggle('on', state.gNamesHidden);
    gTracksBtn.setAttribute('aria-pressed', state.gNamesHidden ? 'true' : 'false');
    gTracksBtn.title = state.gNamesHidden ? 'Show track names' : 'Hide track names';
  }

  if (gCollapseBtn) {
    gCollapseBtn.hidden = false;
    gCollapseBtn.disabled = total === 0;
    gCollapseBtn.classList.toggle('closed', allClosed);
    gCollapseBtn.setAttribute('aria-expanded', allClosed ? 'false' : 'true');
    gCollapseBtn.title = allClosed ? 'Open all tracks' : 'Collapse all tracks';
  }
  if (gEditBtn) gEditBtn.hidden = false;

  // Keep the hidden legacy controls coherent if they are reached by
  // keyboard or by the comparison variants.
  efDom.tracksBtn.hidden = false;
  efDom.tracksBtn.classList.toggle('on', state.gNamesHidden);
  efDom.tracksBtn.setAttribute('aria-pressed', state.gNamesHidden ? 'true' : 'false');
  efDom.collapseAll.disabled = total === 0 || open === 0;
};

setVariant = function (v) {
  if (v !== 'G') {
    delete dom.device.dataset.names;
    if (gTracksBtn) gTracksBtn.hidden = true;
    if (gCollapseBtn) gCollapseBtn.hidden = true;
    if (gEditBtn) gEditBtn.hidden = true;
    if (gExpandAll) gExpandAll.hidden = true;
    if (dom.tplBtn) dom.tplBtn.hidden = false;
    gBaseSetVariant(v);
    return;
  }

  const firstVisit = !gVisited;
  gVisited = true;

  // Reuse E's setup (clear selection, notes, tabs, fit).
  gBaseSetVariant('E');

  state.variant = 'G';
  state.density = 'normal';
  if (firstVisit) {
    state.gNamesHidden = false;
    for (const t of TRACKS) state.trackOpen[t.id] = true;
  }

  dom.device.dataset.variant = 'G';
  dom.device.dataset.density = 'normal';
  dom.device.dataset.names = state.gNamesHidden ? 'hidden' : 'shown';

  document.querySelectorAll('.tab').forEach(b => {
    b.classList.toggle('on', b.dataset.variant === 'G');
  });

  dom.notes.innerHTML = NOTES.G;
  dom.hint.textContent = HINTS.G;
  dom.tplBtn.hidden = true;

  efDom.viewBar.hidden = true;
  efDom.editBtn.hidden = true;
  efDom.appbar.classList.remove('has-sel');
  if (gExpandAll) gExpandAll.hidden = true;
  if (gTracksBtn) gTracksBtn.hidden = false;
  if (gCollapseBtn) gCollapseBtn.hidden = false;
  if (gEditBtn) gEditBtn.hidden = false;

  fitDevice();
  fitTray();
  requestAnimationFrame(renderAll);
};

/* One collapse/expand button: if anything is open, collapse all;
   if everything is closed, open all. */
if (gCollapseBtn) {
  gCollapseBtn.addEventListener('click', () => {
    if (state.variant !== 'G') return;
    const anyOpen = TRACKS.some(t => state.trackOpen[t.id] !== false);
    if (!anyOpen) {
      for (const t of TRACKS) state.trackOpen[t.id] = true;
    } else {
      for (const t of TRACKS) state.trackOpen[t.id] = false;
    }
    closeEFTrackPop();
    renderAll();
  });
}

if (gTracksBtn) {
  gTracksBtn.addEventListener('click', () => {
    if (state.variant !== 'G') return;
    state.gNamesHidden = !state.gNamesHidden;
    closeEFTrackPop();
    renderAll();
  });
}

if (gEditBtn) {
  gEditBtn.addEventListener('click', () => {
    if (state.variant === 'G') openEFCategories();
  });
}

/* ---------- notes ---------- */
NOTES.G = `<h3>Variant G</h3><h2>Streamlined — header first, controls at the bottom</h2>
  <p>This is <b>G</b> with the second row removed. Selecting a block still puts its details in the top row; rows never move. The default is <b>all tracks open</b>, normal-height bars.</p>
  <p><b>Bottom bar:</b> a segmented pair of icon buttons on the left (<b>Tracks</b> and the all-track <b>chevron</b>), a centered <b>time-scale selector</b>, and a square-ish <b>NEW</b> on the right. The chevron points down to collapse everything and up to reopen it.</p>
  <p><b>Categories</b> now opens from <b>✎ Edit</b> at the foot of the name column. It is hidden automatically when Tracks hides the names. The whole timeline is a finite <b>8 days</b>, and the maximum zoom-out shows all of it. The Edit sheet also has <b>Export .json</b> and <b>Import .json</b> for simple sync.</p>
  <p><b>Zoom</b> presets: <b>1h · 3h · 6h · 12h · 1d · 3d · 8d</b>. The top ribbon uses adaptive ticks: hourly numbers at 6–12h (half-hour marks at 8h and 12h, 15-minute ticks at 6h), quarter-hour labels at 1h, 2-hour labels with hourly marks at 1d, and 00/06/12/18 marks at 3d; 8d switches to day labels.</p>
  <ul>
    <li><b>Tracks</b> hides the name column and leaves a <b>3px colour sliver</b>, giving the width to the timeline. The minimap and edit button also disappear.</li>
    <li>With a block selected, the top row is its name + category, the time detail, and edit/undo/lock/Now. With nothing selected it falls back to Timeline + the date. Now and lock stay in the top-right.</li>
    <li>When names are shown, each track's chevron collapses just that track. With names hidden, use the one bottom chevron to reopen everything.</li>
    <li>Everything else from G stays: tap selects, hold+drag moves, edge anchors resize, ✎ opens exact times, categories are editable, layout locks, multi-step undo, vertical track scrolling.</li>
  </ul>
  <p><b>Trade-off:</b> the bottom bar is much quieter, but the icon-only Tracks/chevron controls rely on their tooltips for labels. Templates are not represented in this streamlined mockup yet.</p>
  <hr>
  <p><b>Try it:</b> press the sidebar icon to hide names, then use the centered − / 8h / ＋ control. Press the chevron to collapse everything; it rotates to point up. Open <b>✎ Edit</b> at the bottom of the names column for categories and JSON sync. Select any block: the details stay in the top row and the rows do not move.</p>`;

HINTS.G = 'icons hide names / collapse · centered zoom · 8-day total timeline · ✎ Edit categories + JSON sync · tap selects · hold moves · edge anchors resize';

/* Open the G mockup first; the other tabs stay available for comparison. */
setVariant('G');
renderAll();

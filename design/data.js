/* ---------- basics ---------- */
const HOUR = 3600000;
const DAY = 86400000;

const NOW = (() => { const d = new Date(); d.setSeconds(0, 0); return d.getTime(); })();
const TODAY = (() => { const d = new Date(NOW); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); })();
const startOfDay = ts => { const d = new Date(ts); return new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime(); };

/* The timeline is finite: eight calendar days, with today sitting
   inside the window. Maximum zoom-out shows this entire range. */
const TIMELINE_DAYS = 8;
const TIMELINE_START = startOfDay(NOW) - 4 * DAY;
const TIMELINE_END = TIMELINE_START + TIMELINE_DAYS * DAY;

const TRACKS = [
  { id: 'food',     name: 'Food',     color: '#d9a05b' },
  { id: 'work',     name: 'Work',     color: '#6f9df0' },
  { id: 'personal', name: 'Personal', color: '#72c39a' },
  { id: 'learning', name: 'Learning', color: '#5fc2c9' },
  { id: 'health',   name: 'Health',   color: '#b489e6' },
  { id: 'media',    name: 'Media',    color: '#e08aa0' },
  { id: 'rest',     name: 'Rest',     color: '#6270c9' },
];
const TRACK_BY_ID = Object.fromEntries(TRACKS.map(t => [t.id, t]));

const state = {
  variant: 'A',
  device: 'phone',
  locked: false,
  hours: 8,
  viewStart: NOW - 8 * 0.3 * HOUR,
  selectedId: null,
  undo: [],
  dragging: null,
};

/* ---------- sample data ---------- */
const blocks = [];
let uid = 1;
function addBlock(track, title, start, end, type) {
  blocks.push({ id: uid++, track, title, start, end, type });
}

function mulberry32(a) {
  return function () {
    a |= 0; a = a + 0x6D2B79F5 | 0;
    let t = Math.imul(a ^ a >>> 15, 1 | a);
    t = t + Math.imul(t ^ t >>> 7, 61 | t) ^ t;
    return ((t ^ t >>> 14) >>> 0) / 4294967296;
  };
}

(function generate() {
  for (let d = -12; d <= 12; d++) {
    const base = TODAY + d * DAY;
    const dow = new Date(base).getDay();
    const rnd = mulberry32(9000 + Math.abs(d) * 137 + 11);
    const jit = m => (rnd() * 2 - 1) * m * 60000;

    const breakfast = 8 * HOUR + jit(22);
    const lunch = 13 * HOUR + jit(28);
    const dinner = 19.5 * HOUR + jit(30);

    addBlock('food', 'Breakfast', base + breakfast, base + breakfast + 25 * 60000, 'event');
    addBlock('food', 'Lunch', base + lunch, base + lunch + 35 * 60000, 'event');
    addBlock('food', 'Dinner', base + dinner, base + dinner + 45 * 60000, 'event');
    addBlock('food', 'Digestion', base + breakfast, base + breakfast + 12 * HOUR, 'zone');
    addBlock('food', 'Digestion', base + lunch, base + lunch + 12 * HOUR, 'zone');
    addBlock('food', 'Digestion', base + dinner, base + dinner + 12 * HOUR, 'zone');

    if (dow >= 1 && dow <= 5) {
      addBlock('work', 'Deep work', base + 9.5 * HOUR, base + 12.5 * HOUR, 'event');
      addBlock('work', 'Admin', base + 14 * HOUR, base + 19 * HOUR, 'event');
    } else {
      addBlock('work', 'Side project', base + 11 * HOUR, base + 13 * HOUR, 'event');
    }

    if (rnd() > 0.3) addBlock('personal', 'Walk', base + 18 * HOUR, base + 18.75 * HOUR, 'event');
    if (rnd() > 0.55) addBlock('personal', 'Chores', base + 17 * HOUR, base + 17.5 * HOUR, 'event');

    addBlock('learning', 'Reading', base + 20 * HOUR, base + 20.75 * HOUR, 'event');
    if (rnd() > 0.45) addBlock('health', 'Medication', base + 21 * HOUR, base + 21.08 * HOUR, 'event');
    addBlock('media', 'Wind down', base + 21.5 * HOUR, base + 22.5 * HOUR, 'event');
    addBlock('rest', 'Sleep', base + 23.5 * HOUR, base + 31.5 * HOUR, 'zone');
  }

  addBlock('health', 'Dentist', TODAY + DAY + 11 * HOUR, TODAY + DAY + 12 * HOUR, 'event');
  addBlock('personal', 'Call family', TODAY + 2 * HOUR, TODAY + 2.5 * HOUR, 'event');
})();

/* ---------- formatting ---------- */
const pad2 = n => String(n).padStart(2, '0');
const WD = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const MO = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
const fmtTime = ts => { const d = new Date(ts); return pad2(d.getHours()) + ':' + pad2(d.getMinutes()); };
const fmtDay = ts => { const d = new Date(ts); return WD[d.getDay()] + ' ' + d.getDate(); };
const fmtDayTight = ts => { const d = new Date(ts); return WD[d.getDay()].slice(0, 2) + ' ' + d.getDate(); };
const fmtDayLong = ts => { const d = new Date(ts); return WD[d.getDay()] + ' ' + d.getDate() + ' ' + MO[d.getMonth()]; };
function fmtDur(ms) {
  const m = Math.max(1, Math.round(ms / 60000));
  if (m < 60) return m + 'm';
  const h = Math.floor(m / 60), r = m % 60;
  return r ? h + 'h ' + r + 'm' : h + 'h';
}
function hexA(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16 & 255},${n >> 8 & 255},${n & 255},${a})`;
}
const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));

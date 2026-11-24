// QRQ Trainer in the browser. QRQCore (Swift, compiled to WebAssembly) makes the items, renders the Morse,
// runs the attempt (speed rules, scoring) and analyses results; this file shows it all, plays the sound on the
// AudioContext clock and times the answers. Settings and history live in this browser (localStorage).
//
// ?v=… when published (publish-web.sh stamps it), so the engine and wasm match this page.
const VERSION = new URL(import.meta.url).searchParams.get('v') ?? '';
const v = VERSION ? `?v=${VERSION}` : '';
const engineReady = import(`./engine.js${v}`).then(({ createEngine }) => createEngine(fetch(`qrq.wasm${v}`)));
const DEBUG = new URLSearchParams(location.search).has('debug');

if (VERSION && !DEBUG && 'serviceWorker' in navigator) {
  navigator.serviceWorker.register('sw.js', { scope: './' }).catch(() => { });
}

// MARK: Usage counts (GoatCounter, anonymous, no cookies, nothing stored on the device)

// As in Mock QSO: sent straight to GoatCounter's counting address rather than through its count.js, which always
// adds the page's ?… part. Only the fields below are sent. Not counted on localhost or with ?debug (which logs
// instead); visit the page with #nocount once to stop counting your own visits (#count to start again).
const COUNTER = 'https://g3ajm.goatcounter.com/count';
const counting = (() => {
  try {
    if (location.hash === '#nocount') localStorage.setItem('qrqtrainer.nocount', '1');
    if (location.hash === '#count') localStorage.removeItem('qrqtrainer.nocount');
    if (localStorage.getItem('qrqtrainer.nocount') === '1') return false;
  } catch { }
  return !/^(localhost|127\.|\[::1\])/.test(location.hostname) && location.protocol === 'https:';
})();
function count(fields) {
  const q = new URLSearchParams({ ...fields, s: String(screen.width), rnd: Math.random().toString(36).slice(2) });
  if (DEBUG) { (window.qrqtrainerCounts ??= []).push(Object.fromEntries(q)); console.info('count', Object.fromEntries(q)); return; }
  if (!counting) return;
  try { fetch(`${COUNTER}?${q}`, { mode: 'no-cors', credentials: 'omit', keepalive: true, referrerPolicy: 'no-referrer' }); } catch { }
}
/// A visit: the page's path and title, and where the visitor came from if it was another site.
function countVisit() {
  let from = '';
  try { if (document.referrer && new URL(document.referrer).origin !== location.origin) from = new URL(document.referrer).origin; } catch { }
  count({ p: location.pathname, t: 'QRQ Trainer', ...(from ? { r: from } : {}) });
}
/// Counts an event, e.g. "attempt/callsigns". Only fixed labels are sent: never a callsign, an answer or a list name.
function track(event) {
  count({ p: `qrqtrainer/${event}`, t: event, e: 'true' });
}

const $ = (id) => document.getElementById(id);
const el = (tag, props = {}, ...children) => {
  const node = document.createElement(tag);
  for (const [k, val] of Object.entries(props)) {
    if (val == null || val === false) continue;
    if (k === 'class') node.className = val;
    else if (k === 'style') node.style.cssText = val;
    else if (k.startsWith('on')) node.addEventListener(k.slice(2), val);
    else if (k in node && typeof val !== 'string') node[k] = val;
    else node.setAttribute(k, val === true ? '' : val);
  }
  for (const c of children.flat(Infinity)) if (c != null && c !== false) node.append(c);
  return node;
};
const fill = (node, ...children) => node.replaceChildren(...children.flat(Infinity).filter((c) => c != null && c !== false));
const svg = (tag, attrs = {}, ...children) => {
  const node = document.createElementNS('http://www.w3.org/2000/svg', tag);
  for (const [k, val] of Object.entries(attrs)) if (val != null) node.setAttribute(k, val);
  for (const c of children.flat(Infinity)) if (c != null) node.append(c);
  return node;
};

// MARK: Storage (this browser only)

const store = {
  get(key, fallback) {
    try { const s = localStorage.getItem(`qrq.${key}`); return s == null ? fallback : JSON.parse(s); } catch { return fallback; }
  },
  set(key, value) {
    try { localStorage.setItem(`qrq.${key}`, JSON.stringify(value)); return true; } catch { return false; }
  },
  remove(key) { try { localStorage.removeItem(`qrq.${key}`); } catch { } },
};

// MARK: Settings: the Mac app's preference keys and defaults (Pref in Sources/QRQTrainer/Model/Preferences.swift)

const ALL_CHARACTERS = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ1234567890.,:;+-=\'"?()/@';
const CLASSES = {
  letters: { title: 'Letters', chars: 'ABCDEFGHIJKLMNOPQRSTUVWXYZ' },
  figures: { title: 'Numbers', chars: '1234567890' },
  symbols: { title: 'Symbols', chars: '.,:;+-=\'"?()/@' },
};
const DEFAULTS = {
  count: 50, startCPM: 100, stepPercent: 4, fixedSpeed: false, pauseMs: 400,
  pitch: 600, randomPitch: false, pitchSpread: 100, volume: 0.6, riseMs: 5,
  useImported: false, portablePercent: 0, prefixedPercent: 0, showWPM: false,
  trainerMode: 'callsigns', variableGroupLength: false, groupLength: 5, groupMinLength: 1, groupMaxLength: 12,
  variableWordLength: true, wordLength: 5, wordMinLength: 1, wordMaxLength: 12,
  wordSet: 'top100', bringBackMissedWords: true, groupComposition: 'mixed', enabledCharacters: ALL_CHARACTERS,
  farnsworth: false, farnsworthPercent: 60, insightsRange: 'last50',
};
const settings = { ...DEFAULTS, ...store.get('settings', {}) };
/// Fastest speed: 100 WPM, CWKit's limit (Morse.maxCPM). Older settings may hold a higher start speed.
const MAX_CPM = 500;
settings.startCPM = Math.min(settings.startCPM, MAX_CPM);
let appearance = store.get('appearance', 'system');
/// The imported callsign list: { name, text } (one call per line, already cleaned up by the engine).
let importedList = store.get('list', null);
let importedCount = 0;
/// Finished attempts, as the Mac app's history.json: { id, date, source, config, results }.
let history = store.get('history', []);

function save() { store.set('settings', settings); }
function applyAppearance() {
  if (appearance === 'system') document.documentElement.removeAttribute('data-theme');
  else document.documentElement.dataset.theme = appearance;
}
applyAppearance();

const MODES = [
  [['callsigns', 'Callsigns'], ['hamCodes', 'Ham codes'], ['words', 'Words']],
  [['letters', 'Letters'], ['figures', 'Numbers'], ['symbols', 'Symbols']],
  [['lettersFigures', 'Letters & numbers'], ['lettersSymbols', 'Letters & symbols'], ['figuresSymbols', 'Numbers & symbols'], ['all', 'All characters']],
  [['needsWork', 'Needs work']],
];
const MIN_SAMPLES = 5;

// MARK: Formatting

const unit = () => (settings.showWPM ? 'WPM' : 'CPM');
const speedValue = (cpm, wpm = settings.showWPM) => Math.round(wpm ? cpm / 5 : cpm);
const speed = (cpm, wpm = settings.showWPM) => `${speedValue(cpm, wpm)} ${wpm ? 'WPM' : 'CPM'}`;
const otherSpeed = (cpm) => speed(cpm, !settings.showWPM);
const pct = (x) => `${Math.round(x * 100)}%`;
const ms = (x) => (x == null ? '—' : String(x));
const plural = (n, word) => `${n.toLocaleString('en-GB')} ${word}${n === 1 ? '' : 's'}`;
const cap = (s) => s.charAt(0).toUpperCase() + s.slice(1);
/// Times shown to operators are UTC, e.g. 2026-11-24 1403Z.
function utc(iso) {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return '';
  const p = (n) => String(n).padStart(2, '0');
  return `${d.getUTCFullYear()}-${p(d.getUTCMonth() + 1)}-${p(d.getUTCDate())} ${p(d.getUTCHours())}${p(d.getUTCMinutes())}Z`;
}
function ago(iso) {
  const s = (new Date(iso).getTime() - Date.now()) / 1000;
  const rtf = new Intl.RelativeTimeFormat('en-GB', { numeric: 'auto' });
  for (const [u, n] of [['year', 31536000], ['month', 2592000], ['week', 604800], ['day', 86400], ['hour', 3600], ['minute', 60]]) {
    if (Math.abs(s) >= n) return rtf.format(Math.round(s / n), u);
  }
  return 'just now';
}
/// Red below 50%, through orange and yellow, to green at 100% (the Mac app's AccuracyColor).
function accuracyColour(a, alpha = 1) {
  if (a == null) return `color-mix(in srgb, var(--muted) ${Math.round(alpha * 25)}%, transparent)`;
  const t = Math.max(0, Math.min(1, (a - 0.5) / 0.5));
  return `hsl(${Math.round(119 * t)} 69% 55% / ${alpha})`;
}
let morseCodes = {};
const morse = (c) => (morseCodes[c] ?? '').replaceAll('.', '·').replaceAll('-', '–');

// MARK: Attempts

const record = {
  score: (r) => r.results.reduce((s, x) => s + x.points, 0),
  correct: (r) => r.results.filter((x) => x.sent === x.received).length,
  peak: (r) => Math.max(0, ...r.results.filter((x) => x.sent === x.received).map((x) => x.cpm)),
  average: (r) => (r.results.length ? r.results.reduce((s, x) => s + x.cpm, 0) / r.results.length : 0),
  accuracy: (r) => (r.results.length ? record.correct(r) / r.results.length : 0),
  response(r) {
    const t = r.results.map((x) => x.responseMs).filter((x) => x != null);
    return t.length ? Math.trunc(t.reduce((a, b) => a + b, 0) / t.length) : null;
  },
};
const byDate = (a, b) => (a.date < b.date ? -1 : a.date > b.date ? 1 : 0);
/// Attempts of one kind and length, oldest first. Best scores are only compared between these: a 10-item attempt can't
/// be compared with a 50-item one.
const recordsFor = (source, count) => history.filter((r) => r.source === source && r.config?.count === count).sort(byDate);
function bestFor(source, count) {
  let best = null;
  for (const r of recordsFor(source, count)) if (!best || record.score(r) > record.score(best)) best = r;
  return best;
}
function rangeRecords() {
  const all = [...history].sort(byDate);
  const limit = { last10: 10, last50: 50 }[settings.insightsRange];
  return limit ? all.slice(-limit) : all;
}
function saveHistory() {
  if (!store.set('history', history)) toast('This browser is out of room, so the history couldn’t be saved.');
  needsWorkCache = null;
}

// MARK: Engine

let engine = null;
let needsWorkCache = null;
/// The characters Insights lists under Needs work (from the attempts in its range), for the Needs work mode.
function needsWork() {
  if (needsWorkCache == null) {
    needsWorkCache = engine.call('analyse', { results: rangeRecords().flatMap((r) => r.results), minSamples: MIN_SAMPLES }).needsWork;
  }
  return needsWorkCache;
}
function engineSettings() {
  return { ...settings, listName: importedList?.name ?? '', needsWorkCharacters: settings.trainerMode === 'needsWork' ? needsWork() : '' };
}
let exampleSeed = Math.floor(Math.random() * 1e9);
const describe = () => engine.call('describe', { settings: engineSettings(), seed: exampleSeed });

// MARK: Audio

let ctx = null;
let source = null;
function audio() {
  if (!ctx) {
    ctx = new (window.AudioContext || window.webkitAudioContext)();
    try { if (navigator.audioSession) navigator.audioSession.type = 'playback'; } catch { }
  }
  if (ctx.state !== 'running') ctx.resume();
  return ctx;
}
function stopSound() {
  if (source) { source.onended = null; try { source.stop(); } catch { } source = null; }
}
/// performance.now() time at which context time `t` is heard: the output timestamp where the browser gives one
/// (it allows for the output latency, large for Bluetooth headphones), otherwise now plus the reported latency.
function heardAt(t) {
  const c = ctx;
  const ts = c.getOutputTimestamp?.();
  if (ts && ts.contextTime > 0 && ts.performanceTime > 0) return ts.performanceTime + (t - ts.contextTime) * 1000;
  return performance.now() + (t - c.currentTime + (c.outputLatency || c.baseLatency || 0)) * 1000;
}
/// Plays samples (rendered at the context's rate). Returns when the first sample is heard, in performance.now() time.
function playSamples(samples, onEnded) {
  stopSound();
  const c = audio();
  const buffer = c.createBuffer(1, Math.max(1, samples.length), c.sampleRate);
  buffer.copyToChannel(samples, 0);
  const node = c.createBufferSource();
  node.buffer = buffer;
  node.connect(c.destination);
  const at = c.currentTime + 0.03;
  node.onended = () => { if (source === node) { source = null; onEnded?.(); } };
  node.start(at);
  source = node;
  return heardAt(at);
}

let testTonePlaying = false;
function toggleTestTone() {
  if (testTonePlaying) { stopSound(); testTonePlaying = false; refreshTestTone(); return; }
  if (trainer.phase === 'running' || !engine) return;
  const { samples } = engine.call('testTone', { settings: engineSettings() }, { sampleRate: audio().sampleRate, audio: true });
  testTonePlaying = true;
  playSamples(samples, () => { testTonePlaying = false; refreshTestTone(); });
  refreshTestTone();
}
function stopTestTone() { if (testTonePlaying) { stopSound(); testTonePlaying = false; refreshTestTone(); } }
function refreshTestTone() {
  for (const b of document.querySelectorAll('[data-test-tone]')) b.textContent = testTonePlaying ? 'Stop' : b.dataset.testTone;
}

// MARK: The trainer (TrainerModel in the Mac app)

const trainer = {
  phase: 'idle', // idle | running | finished
  state: null, // the engine's answer: index, total, cpm, score, progress, config
  source: '',
  itemName: 'callsign',
  results: [],
  last: null, // { result, detail }
  playing: false,
  awaiting: false,
  soundStarts: 0, // performance.now() when the first tone is heard
  firstKeyAt: null,
  timer: 0,
  previousBest: null,
  finished: null, // the saved record
};

function start() {
  if (trainer.phase === 'running' || !engine) return;
  stopTestTone();
  const info = describe();
  if (!info.canStart) return;
  const earlier = settings.trainerMode === 'words' && settings.bringBackMissedWords
    ? history.filter((r) => r.source.startsWith('Words')).sort(byDate).flatMap((r) => r.results) : [];
  audio(); // inside the click, so the browser lets it play
  const state = engine.call('start', { settings: engineSettings(), earlier });
  Object.assign(trainer, {
    phase: 'running', state, source: state.source, itemName: info.itemName, results: [], last: null,
    playing: false, awaiting: false, firstKeyAt: null, finished: null,
    previousBest: bestFor(state.source, state.config.count) ? record.score(bestFor(state.source, state.config.count)) : null,
  });
  render();
  schedule(0.8);
  const band = Math.floor(settings.startCPM / 50) * 50;
  track(`attempt/${settings.trainerMode}${settings.trainerMode === 'callsigns' && settings.useImported && importedCount ? ' (imported list)' : ''}`);
  track(`speed/${band}-${band + 49} cpm${settings.fixedSpeed ? ' fixed' : ''}${settings.farnsworth ? ' farnsworth' : ''}`);
  track(`length/${settings.count}`);
}

function schedule(seconds) {
  clearTimeout(trainer.timer);
  trainer.timer = setTimeout(playCurrent, Math.max(0, seconds) * 1000);
}

function playCurrent(repeat = false) {
  if (trainer.phase !== 'running') return;
  const { result, samples } = engine.call('play', { repeat }, { sampleRate: audio().sampleRate, audio: true });
  trainer.state = result;
  trainer.awaiting = true;
  trainer.playing = true;
  const heard = playSamples(samples, () => { trainer.playing = false; updateCopying(); });
  trainer.soundStarts = heard + result.leadIn * 1000;
  trainer.soundSeconds = result.soundSeconds;
  if (!copying.entry?.value) trainer.firstKeyAt = null;
  updateCopying();
}

function repeatCurrent() {
  if (trainer.phase !== 'running' || !trainer.awaiting) return;
  playCurrent(true);
}

function submit(at = performance.now()) {
  if (trainer.phase !== 'running' || !trainer.awaiting) return;
  const answer = copying.entry.value;
  const responseTime = (at - trainer.soundStarts) / 1000;
  const firstKeyTime = trainer.firstKeyAt == null ? null : (trainer.firstKeyAt - trainer.soundStarts) / 1000;
  const state = engine.call('submit', { answer, responseTime, ...(firstKeyTime == null ? {} : { firstKeyTime }) });
  trainer.state = state;
  trainer.results.push(state.result);
  trainer.last = { result: state.result, detail: state.detail };
  trainer.awaiting = false;
  trainer.firstKeyAt = null;
  copying.entry.value = '';
  stopSound();
  trainer.playing = false;
  if (state.finished) finish();
  else { updateCopying(); schedule(settings.pauseMs / 1000); }
}

function abort() {
  if (trainer.phase === 'running') track('ended early');
  clearTimeout(trainer.timer);
  stopSound();
  engine?.call('end');
  Object.assign(trainer, { phase: 'idle', playing: false, awaiting: false, state: null });
  render();
}

function finish() {
  const s = trainer.state;
  const rec = {
    id: crypto.randomUUID?.() ?? String(Date.now()),
    date: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
    source: trainer.source,
    config: s.config,
    results: trainer.results,
  };
  history.push(rec);
  saveHistory();
  engine.call('end');
  trainer.finished = rec;
  track(`finished/${settings.trainerMode}`);
  trainer.phase = 'finished';
  render();
}

// MARK: Views

let view = 'train';
const copying = {};

function render() {
  const running = trainer.phase === 'running';
  $('tabs').hidden = running;
  $('settingsBtn').disabled = running;
  for (const b of $('tabs').children) b.setAttribute('aria-selected', String(b.dataset.view === view));
  if (!engine) return;
  if (view === 'train' || running) {
    if (trainer.phase === 'running') renderCopying();
    else if (trainer.phase === 'finished') renderResults();
    else renderReady();
  } else if (view === 'insights') renderInsights();
  else renderHistory();
}

$('tabs').addEventListener('click', (e) => {
  const b = e.target.closest('button[data-view]');
  if (!b) return;
  view = b.dataset.view;
  if (view !== 'train') track(`view/${view}`);
  if (view === 'train' && trainer.phase === 'finished') trainer.phase = 'idle';
  stopTestTone();
  render();
  window.scrollTo(0, 0);
});

/// A segmented control. `options`: [[value, label], …].
function segmented(options, value, onChange, cls = '') {
  return el('div', { class: `seg inline ${cls}`, role: 'group' },
    options.map(([val, label]) => el('button', {
      type: 'button', 'aria-pressed': String(val === value),
      onclick: () => { if (val !== value) onChange(val); },
    }, label)));
}
function stepper(value, min, max, onChange, step = 1, format = String) {
  return el('span', { class: 'stepper' },
    el('button', { type: 'button', 'aria-label': 'Less', disabled: value <= min, onclick: () => onChange(Math.max(min, +(value - step).toFixed(2))) }, '−'),
    el('output', {}, format(value)),
    el('button', { type: 'button', 'aria-label': 'More', disabled: value >= max, onclick: () => onChange(Math.min(max, +(value + step).toFixed(2))) }, '+'));
}
function toggle(checked, onChange, label) {
  return el('label', { class: 'switch' },
    el('input', { type: 'checkbox', checked, 'aria-label': label, onchange: (e) => onChange(e.target.checked) }), el('span'));
}
function tile(title, value, detail, colour) {
  return el('div', { class: 'tile' },
    el('div', { class: 't', style: `color:${colour}` }, title),
    el('div', { class: 'v' }, value),
    detail ? el('div', { class: 'd' }, detail) : null);
}
function set(key, value, { rerender = true } = {}) {
  settings[key] = value;
  save();
  if (rerender) render();
}

// MARK: Ready

function renderReady() {
  const info = describe();
  const item = info.itemName;
  const source = info.source;
  const attempts = recordsFor(source, settings.count);
  const best = bestFor(source, settings.count);
  const peak = attempts.length ? Math.max(...attempts.map(record.peak)) : null;
  const fixed = settings.fixedSpeed;

  const speedNumber = el('span', { class: 'big' }, String(speedValue(settings.startCPM)));
  const slider = el('input', {
    type: 'range', min: 25, max: MAX_CPM, step: 5, value: settings.startCPM, 'aria-label': fixed ? 'Speed' : 'Start speed',
    oninput: (e) => { settings.startCPM = +e.target.value; speedNumber.textContent = String(speedValue(settings.startCPM)); save(); },
    onchange: () => render(),
  });
  const suggested = best ? Math.max(25, Math.min(MAX_CPM, Math.round(record.peak(best) * 0.8 / 5) * 5)) : null;

  fill($('view'),
    el('h2', { class: 'title' }, 'Ready to copy'),
    el('p', { class: 'lede' }, fixed
      ? `Listen to each ${item}, type it, press Return. Every ${item} is sent at the same speed.`
      : `Listen to each ${item}, type it, press Return. Copy correctly and the speed goes up; miss and it drops.`),
    whatToCopy(info),
    el('div', { class: 'grid2 wide-left', style: 'margin-bottom:16px' },
      el('div', { class: 'card' },
        el('div', { class: 'card-head' },
          el('h3', {}, fixed ? 'Speed' : 'Start speed'),
          segmented([[false, 'Adaptive'], [true, 'Fixed']], fixed, (val) => set('fixedSpeed', val), 'small')),
        el('div', { class: 'speed-line' }, speedNumber, el('span', { class: 'unit' }, unit()),
          el('button', { class: 'btn', type: 'button', 'data-test-tone': 'Test tone', title: 'Hear this speed and your audio settings', onclick: toggleTestTone }, testTonePlaying ? 'Stop' : 'Test tone')),
        slider,
        el('div', { class: 'range-labels' }, el('span', {}, String(speedValue(25))), el('span', {}, String(speedValue(MAX_CPM)))),
        suggested ? el('button', { class: 'link-btn', type: 'button', onclick: () => set('startCPM', suggested) },
          `Use ${speed(suggested)} (80% of your peak)`) : null,
        settings.farnsworth ? el('p', { class: 'note' }, `Farnsworth spacing: overall ${settings.farnsworthPercent}% of character speed`) : null),
      el('div', { class: 'card' },
        el('div', { class: 'card-head' }, el('h3', {}, `${cap(item)}s per attempt`)),
        segmented([[10, '10'], [25, '25'], [50, '50'], [100, '100']], settings.count, (val) => set('count', val)),
        el('p', { class: 'note' }, settings.count === 50 ? '50 is the classic attempt length, so scores stay comparable.'
          : settings.count > 50 ? 'Long attempts build stamina.' : 'Shorter attempts are good for warming up.'),
        )),
    el('p', { class: 'note', style: 'margin:0 0 10px', title: 'Best score, peak speed and attempts count only attempts of this kind and length' },
      'Your scores for: ', el('b', { style: 'color:var(--text)' }, info.caption)),
    el('div', { class: 'tiles' },
      tile('Best score', best ? String(record.score(best)) : '—', best ? utc(best.date) : null, 'var(--gold)'),
      tile('Peak speed', peak ? speed(peak) : '—', null, 'var(--warn)'),
      tile('Attempts', String(attempts.length), attempts.length ? `Last: ${record.score(attempts.at(-1))} points` : null, 'var(--accent)')),
    el('div', { class: 'start-row' },
      el('button', { class: 'btn primary', type: 'button', disabled: !info.canStart, onclick: start },
        svg('svg', { viewBox: '0 0 24 24', fill: 'currentColor', width: 18, height: 18 }, svg('path', { d: 'M8 5v14l11-7z' })), 'Start attempt')),
    el('section', { class: 'help' }, $('helpTemplate').content.cloneNode(true), $('aboutTemplate').content.cloneNode(true)),
  );
}

function whatToCopy(info) {
  const mode = settings.trainerMode;
  const select = el('select', { class: 'mode', 'aria-label': 'What to copy', onchange: (e) => set('trainerMode', e.target.value) },
    MODES.map((group, i) => el('optgroup', { label: ['Practice', 'Characters', 'Combinations', 'Your weak spots'][i] },
      group.map(([val, label]) => el('option', { value: val, selected: val === mode }, label)))));
  const body = [];
  const classTitles = info.classes.map((c) => CLASSES[c].title.toLowerCase());
  const classList = (joiner) => (classTitles.length > 1 ? `${classTitles.slice(0, -1).join(', ')} ${joiner} ${classTitles.at(-1)}` : classTitles[0] ?? '');
  if (mode === 'needsWork') {
    const chars = info.needsWork;
    if (!chars) {
      body.push(el('p', { class: 'note', style: 'margin:0' }, `Not enough history yet. Once each character has been copied ${MIN_SAMPLES} times, the ones that need work are practised here.`));
    } else {
      body.push(el('div', { class: 'opt' }, el('span', { class: 'label' }, 'The characters Insights says need work. They update as you improve.'),
        el('div', { class: 'chips' }, [...chars].map((c) => el('span', { class: 'chip focus' }, c)))));
      body.push(el('div', { style: 'margin-top:16px' }, lengthControl('Group length', 'variableGroupLength', 'groupLength', 'groupMinLength', 'groupMaxLength', 'characters')));
    }
  } else if (info.classes.length) {
    body.push(el('div', { class: 'row-opts' },
      lengthControl('Group length', 'variableGroupLength', 'groupLength', 'groupMinLength', 'groupMaxLength', 'characters'),
      info.classes.length > 1 ? el('div', { class: 'opt', title: `Mixed: any group can combine ${classList('and')}. Separated: each group uses only one of them.` },
        el('span', { class: 'label' }, 'Composition'),
        segmented([['mixed', 'Mixed'], ['separated', 'Separated']], settings.groupComposition, (val) => set('groupComposition', val))) : null,
      el('div', { class: 'opt' }, el('span', { class: 'label' }, 'Characters'),
        el('button', { class: 'btn', type: 'button', onclick: () => openCharacters(info.classes) }, `${info.selected} of ${info.classTotal}`))));
    if (!info.canStart) body.push(el('p', { class: 'warn' }, `Select at least one ${classList('or')} character to start.`));
  } else if (mode === 'callsigns') {
    body.push(el('div', { class: 'line', style: 'display:flex;gap:12px;align-items:center;flex-wrap:wrap' },
      el('span', {}, info.source),
      el('button', { class: 'link-btn', type: 'button', onclick: () => openSettings('callsigns') }, 'Callsign settings…')));
  } else if (mode === 'words') {
    body.push(el('div', { class: 'row-opts' },
      el('div', { class: 'opt', title: 'Start with the 100 most common words. A smaller set means you hear each word more often.' },
        el('span', { class: 'label' }, 'Word set'),
        segmented([['top100', 'Top 100'], ['top200', 'Top 200'], ['all', 'All']], settings.wordSet, (val) => set('wordSet', val))),
      lengthControl('Word length', 'variableWordLength', 'wordLength', 'wordMinLength', 'wordMaxLength', 'letters'),
      el('div', { class: 'opt' }, el('span', { class: 'label' }, 'Words'), el('span', { class: 'num', style: 'min-height:38px;display:flex;align-items:center' }, `${info.wordCount} of ${info.wordTotal}`))));
    body.push(el('div', { class: 'switch-line', title: 'A missed word is sent again 3 words later, and words you missed last time come back in the next attempt' },
      toggle(settings.bringBackMissedWords, (val) => set('bringBackMissedWords', val), 'Bring back missed words'), el('span', {}, 'Bring back missed words')));
    if (!info.canStart) body.push(el('p', { class: 'warn' }, 'No words of that length in this set. Choose a different length or set to start.'));
  } else {
    body.push(el('p', { class: 'note', style: 'margin:0' }, 'Q codes, abbreviations and reports such as QTH, TNX and 5NN.'));
  }
  return el('div', { class: 'card' },
    el('div', { class: 'card-head' }, el('h3', {}, 'What to copy'), select),
    body,
    el('div', { class: 'examples' }, el('span', { class: 'muted' }, 'Example'),
      el('span', { class: 'mono', title: 'Click for other examples', style: 'cursor:pointer', onclick: () => { exampleSeed++; render(); } }, info.examples.join('  '))));
}

/// Fixed or variable length, with steppers for the length or the min–max range (lengths 1–12).
function lengthControl(title, variableKey, fixedKey, minKey, maxKey, noun) {
  const variable = settings[variableKey];
  const line = [segmented([[false, 'Fixed'], [true, 'Variable']], variable, (val) => set(variableKey, val))];
  if (variable) {
    const lo = settings[minKey], hi = settings[maxKey];
    line.push(stepper(lo, 1, Math.max(1, Math.min(hi, 12)), (val) => set(minKey, val)), el('span', { class: 'muted' }, 'to'),
      stepper(hi, Math.min(12, Math.max(lo, 1)), 12, (val) => set(maxKey, val)));
  } else {
    line.push(stepper(settings[fixedKey], 1, 12, (val) => set(fixedKey, val)));
  }
  line.push(el('span', { class: 'muted' }, noun));
  return el('div', { class: 'opt' }, el('span', { class: 'label' }, title), el('div', { class: 'line' }, line));
}

// MARK: Copying

function renderCopying() {
  const R = 46, C = 2 * Math.PI * R;
  copying.fg = svg('circle', { class: 'fg', cx: 50, cy: 50, r: R, fill: 'none', 'stroke-width': 5, 'stroke-linecap': 'round', 'stroke-dasharray': C, 'stroke-dashoffset': C });
  copying.circumference = C;
  copying.counter = el('span');
  copying.score = el('span', { class: 'num' }, '0');
  copying.wave = el('div', { class: 'wave', 'aria-hidden': 'true' }, el('i'), el('i'), el('i'), el('i'), el('i'));
  copying.speed = el('span', { class: 'num' });
  copying.trend = el('span', { class: 'trend' });
  copying.sub = el('div', { class: 'sub' });
  copying.feedback = el('div', { class: 'feedback', 'aria-live': 'polite' });
  copying.repeat = el('button', { class: 'btn', type: 'button', onclick: repeatCurrent }, 'Repeat');
  copying.entry = el('input', {
    class: 'entry', type: 'text', autocomplete: 'off', autocapitalize: 'characters', autocorrect: 'off', spellcheck: false,
    enterkeyhint: 'go', 'aria-label': 'What you heard', maxLength: 20,
    oninput: (e) => {
      // Upper case, plain quotes, and only characters Morse has codes for.
      const clean = e.target.value.toUpperCase().replace(/[‘’]/g, "'").replace(/[“”]/g, '"')
        .split('').filter((c) => ALL_CHARACTERS.includes(c)).join('').slice(0, 20);
      if (clean !== e.target.value) e.target.value = clean;
      if (trainer.firstKeyAt == null && trainer.awaiting && clean) trainer.firstKeyAt = e.timeStamp || performance.now();
    },
    onkeydown: (e) => {
      if (e.key === 'Enter' && !e.isComposing) { e.preventDefault(); submit(e.timeStamp || performance.now()); }
    },
  });
  fill($('view'), el('div', { class: 'copying' },
    el('div', { class: 'top' }, copying.counter,
      el('span', { class: 'score' }, svg('svg', { viewBox: '0 0 24 24', fill: 'currentColor' }, svg('path', { d: 'M12 2l3 6.9 7.5.7-5.7 5 1.7 7.4L12 18.3 5.5 22l1.7-7.4-5.7-5 7.5-.7z' })), copying.score)),
    el('div', { class: 'ring', role: 'img' },
      svg('svg', { class: 'track', viewBox: '0 0 100 100' }, svg('circle', { class: 'bg', cx: 50, cy: 50, r: R, fill: 'none', 'stroke-width': 5 }), copying.fg),
      el('div', { class: 'centre' }, copying.wave, el('div', { class: 'speed' }, copying.speed, copying.trend), copying.sub)),
    copying.entry,
    copying.feedback,
    el('div', { class: 'controls' },
      copying.repeat, el('kbd', { class: 'desk' }, 'F6'), el('span', { class: 'muted', style: 'font-size:14px' }, 'no points for a repeat'),
      el('span', { class: 'spacer' }),
      el('kbd', { class: 'desk' }, 'esc'), el('button', { class: 'btn danger', type: 'button', onclick: abort }, 'End attempt'))));
  copying.entry.focus();
  updateCopying();
}

function updateCopying() {
  if (trainer.phase !== 'running' || !copying.entry?.isConnected) return;
  const s = trainer.state;
  copying.counter.textContent = `${cap(trainer.itemName)} ${Math.min(s.index + 1, s.total)} of ${s.total}`;
  copying.score.textContent = String(s.score);
  copying.fg.setAttribute('stroke-dashoffset', String(copying.circumference * (1 - Math.max(0.001, s.progress))));
  copying.wave.classList.toggle('on', trainer.playing);
  copying.speed.textContent = String(speedValue(s.cpm));
  const trend = trainer.last ? (trainer.last.result.sent === trainer.last.result.received ? 1 : -1) : 0;
  copying.trend.textContent = trend > 0 ? '↑' : trend < 0 ? '↓' : '';
  copying.trend.className = `trend ${trend > 0 ? 'up' : trend < 0 ? 'down' : ''}`;
  copying.sub.textContent = `${unit()}  ·  ${otherSpeed(s.cpm)}`;
  copying.entry.placeholder = trainer.awaiting ? 'Type what you heard' : 'Get ready…';
  copying.repeat.disabled = !trainer.awaiting;
  $('view').querySelector('.ring').setAttribute('aria-label', `Speed ${speed(s.cpm)}, ${Math.round(s.progress * 100)} percent complete`);
  const last = trainer.last;
  if (last && copying.shown !== last.result.index) {
    copying.shown = last.result.index;
    const r = last.result, ok = r.sent === r.received;
    fill(copying.feedback, el('div', { class: 'fb' },
      el('span', { class: `mark ${ok ? 'good' : 'bad'}` }, ok ? '✓' : '✗'),
      el('div', {}, el('div', { class: 'sent' }, r.sent),
        !ok ? el('div', { class: 'copied' }, diff(r, last.detail)) : r.repeated ? el('small', {}, 'Repeated') : null),
      el('div', { class: 'pts' }, el('b', {}, `+${r.points}`), el('span', { class: 'muted' }, ` / ${last.detail.maxPoints}`),
        el('small', {}, `${speed(r.cpm)} · ${r.responseMs == null ? '—' : `${r.responseMs} ms`}`))));
  }
}

/// What was typed, with mistakes coloured: wrong in red, extra faded red, missing as an orange underscore.
function diff(result, detail) {
  if (!result.received) return el('span', { class: 'muted' }, '—');
  return el('span', {}, detail.align.map(([kind, , typed]) =>
    kind === 'match' ? typed : kind === 'wrong' ? el('span', { class: 'd-wrong' }, typed)
      : kind === 'extra' ? el('span', { class: 'd-extra' }, typed) : el('span', { class: 'd-missing' }, '_')));
}

// MARK: Results

function renderResults() {
  const rec = trainer.finished;
  const score = record.score(rec);
  const isNewBest = score > 0 && score > (trainer.previousBest ?? 0);
  fill($('view'),
    el('div', { style: 'display:flex;align-items:center;gap:12px;flex-wrap:wrap' },
      el('div', { style: 'flex:1;min-width:0' }, el('h2', { class: 'title' }, 'Attempt complete'), el('p', { class: 'lede' }, `${rec.source} · ${utc(rec.date)}`)),
      isNewBest ? el('span', { class: 'best' }, '🏆 New personal best') : null),
    summaryTiles(rec, trainer.previousBest),
    el('div', { class: 'card' }, el('div', { class: 'card-head' }, el('h3', {}, 'Speed through the attempt')), speedChart(rec)),
    el('div', { class: 'card', style: 'padding:6px 4px' }, resultsTable(rec)),
    el('div', { class: 'start-row' },
      el('button', { class: 'btn primary', type: 'button', onclick: start }, 'New attempt'),
      el('button', { class: 'btn', type: 'button', style: 'min-height:52px', onclick: () => { trainer.phase = 'idle'; render(); } }, 'Done')));
  window.scrollTo(0, 0);
}

function summaryTiles(rec, previousBest) {
  const peak = record.peak(rec), avg = record.average(rec);
  return el('div', { class: 'tiles' },
    tile('Score', String(record.score(rec)), previousBest != null ? `Previous best ${previousBest}` : null, 'var(--gold)'),
    tile('Correct', `${record.correct(rec)}/${rec.results.length}`, pct(record.accuracy(rec)), 'var(--good)'),
    tile('Peak speed', speed(peak), otherSpeed(peak), 'var(--warn)'),
    tile('Average', speed(avg), `${rec.config.stepPercent === 0 ? 'Fixed at' : 'Started at'} ${speed(rec.config.startCPM)}`, 'var(--accent)'),
    tile('Response (ms)', ms(record.response(rec)), 'Average time to answer', 'var(--muted)'));
}

/// Speed for each item: a line, with a green dot for each copy and a red one for each miss.
function speedChart(rec) {
  const pts = rec.results.map((r) => ({ x: r.index + 1, y: speedValue(r.cpm), ok: r.sent === r.received }));
  const W = 640, H = 210, L = 40, Rm = 10, T = 24, B = 26;
  if (!pts.length) return el('p', { class: 'muted' }, 'No items.');
  let lo = Math.min(...pts.map((p) => p.y)), hi = Math.max(...pts.map((p) => p.y));
  if (hi - lo < 4) { lo -= 2; hi += 2; }
  const pad = (hi - lo) * 0.1; lo = Math.max(0, lo - pad); hi += pad;
  const n = Math.max(2, pts.length);
  const X = (x) => L + ((x - 1) / (n - 1)) * (W - L - Rm);
  const Y = (y) => T + (1 - (y - lo) / (hi - lo)) * (H - T - B);
  const ticks = [lo, (lo + hi) / 2, hi].map(Math.round);
  return svg('svg', { class: 'chart', viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': 'Speed through the attempt' },
    ticks.map((t) => [svg('line', { class: 'grid', x1: L, x2: W - Rm, y1: Y(t), y2: Y(t) }), svg('text', { x: L - 6, y: Y(t) + 4, 'text-anchor': 'end' }, String(t))]),
    svg('text', { x: 4, y: 12 }, unit()),
    svg('text', { x: X(1), y: H - 6, 'text-anchor': 'middle' }, '1'),
    svg('text', { x: X(pts.length), y: H - 6, 'text-anchor': 'middle' }, String(pts.length)),
    svg('polyline', { points: pts.map((p) => `${X(p.x)},${Y(p.y)}`).join(' '), fill: 'none', stroke: 'var(--accent)', 'stroke-opacity': 0.55, 'stroke-width': 2, 'stroke-linejoin': 'round' }),
    pts.map((p) => svg('circle', { cx: X(p.x), cy: Y(p.y), r: 3.6, fill: p.ok ? 'var(--good)' : 'var(--bad)' }, svg('title', {}, `${p.x}: ${p.y} ${unit()}, ${p.ok ? 'copied' : 'missed'}`))));
}

function resultsTable(rec) {
  const details = engine.call('details', { results: rec.results });
  return el('div', { class: 'table-wrap' }, el('table', {},
    el('thead', {}, el('tr', {}, ['#', '', 'Sent', 'Copied', `Speed (${unit()})`, 'Response (ms)', 'Max points', 'Points'].map((h) => el('th', {}, h)))),
    el('tbody', {}, rec.results.map((r, i) => {
      const ok = r.sent === r.received;
      return el('tr', {},
        el('td', { class: 'muted' }, String(r.index + 1)),
        el('td', { class: ok ? 'good' : 'bad' }, ok ? '✓' : '✗'),
        el('td', { class: 'mono' }, r.sent),
        el('td', { class: 'mono' }, diff(r, details[i])),
        el('td', {}, String(speedValue(r.cpm))),
        el('td', { title: r.soundMs != null ? `From the start of the sound. It lasted ${r.soundMs} ms.` : '' }, ms(r.responseMs)),
        el('td', { class: 'muted' }, String(details[i].maxPoints)),
        el('td', {}, String(r.points), r.repeated ? el('span', { class: 'muted', title: 'Repeated' }, ' ↺') : null));
    }))));
}

// MARK: Insights

function renderInsights() {
  if (!history.length) {
    fill($('view'), el('div', { class: 'empty' }, el('b', {}, 'No attempts yet'), 'Finish an attempt and you’ll see which characters you copy best and which need work.'));
    return;
  }
  const records = rangeRecords();
  const results = records.flatMap((r) => r.results);
  const a = engine.call('analyse', { results, minSamples: MIN_SAMPLES });
  needsWorkCache = a.needsWork;
  const answered = results.length;
  const correctItems = results.filter((r) => r.sent === r.received).length;
  const peak = records.length ? Math.max(...records.map(record.peak)) : 0;
  const notEnough = () => el('p', { class: 'muted', style: 'font-size:15px' }, `Not enough data yet. Each character needs ${MIN_SAMPLES} copies.`);

  fill($('view'),
    el('div', { class: 'toolbar' }, el('h2', { class: 'title', style: 'margin:0' }, 'Insights'), el('span', { class: 'spacer' }),
      segmented([['last10', 'Last 10'], ['last50', 'Last 50'], ['all', 'All']], settings.insightsRange, (val) => { set('insightsRange', val, { rerender: false }); needsWorkCache = null; render(); }, 'small')),
    el('div', { class: 'tiles' },
      tile('Character accuracy', a.charsSent ? pct(a.charsCorrect / a.charsSent) : '—', plural(a.charsSent, 'character'), 'var(--accent)'),
      tile('Instant recognition', a.ranked ? `${a.instantCount} of ${a.ranked}` : '—', 'characters with ⚡', 'var(--good)'),
      tile('Copy accuracy', answered ? pct(correctItems / answered) : '—', `${answered.toLocaleString('en-GB')} items copied`, 'var(--accent)'),
      tile('Peak speed', peak ? speed(peak) : '—', null, 'var(--warn)'),
      tile('Attempts', String(records.length), records.length ? `Last ${ago(records.at(-1).date)}` : null, 'var(--muted)')),
    el('div', { class: 'grid2', style: 'margin-bottom:16px' },
      el('div', { class: 'card' },
        el('div', { class: 'card-head' }, el('h3', { style: 'color:var(--warn)' }, '⚠ Needs work'),
          a.weakest.length ? el('button', { class: 'btn', type: 'button', title: 'Switch Train to Needs work mode, which sends groups of these characters',
            onclick: () => { track('insights/practise these'); set('trainerMode', 'needsWork', { rerender: false }); view = 'train'; render(); window.scrollTo(0, 0); } }, '▶ Practise these') : null),
        a.weakest.length ? a.weakest.map((s) => charRow(s, true)) : notEnough()),
      el('div', { class: 'card' },
        el('div', { class: 'card-head' }, el('h3', { style: 'color:var(--good)', title: 'Characters you copy correctly and answer quickly, without having to work them out' }, '⚡ Instant recognition')),
        !a.ranked ? notEnough() : a.strongest.length ? a.strongest.map((s) => charRow(s, false))
          : el('p', { class: 'muted', style: 'font-size:15px' }, 'No characters with ⚡ yet. A character earns it when you copy it correctly at least 90% of the time and start typing within 1 second of the sound ending at least 80% of the time.'))),
    el('div', { class: 'card' },
      el('div', { class: 'card-head' }, el('h3', {}, 'Every character'),
        el('span', { class: 'legend' }, '≤50%', el('i', { style: `background:linear-gradient(90deg,${[0.5, 0.625, 0.75, 0.875, 1].map((x) => accuracyColour(x)).join(',')})` }), '100%')),
      el('div', { class: 'cells' }, a.grid.map(cell))),
    el('div', { class: 'grid2', style: 'margin-bottom:16px' },
      el('div', { class: 'card' }, el('div', { class: 'card-head' }, el('h3', {}, 'Common mix-ups')),
        a.confusions.length ? a.confusions.map((c) => el('div', { class: 'mixup', title: c.typed ? `${c.sent} was sent, you typed ${c.typed}` : `${c.sent} was sent, you left it out` },
          el('span', { class: 'c' }, c.sent), el('span', { class: 'morse' }, morse(c.sent)), el('span', { class: 'muted' }, '→'),
          c.typed ? [el('span', { class: 'c bad' }, c.typed), el('span', { class: 'morse' }, morse(c.typed))] : el('span', { class: 'muted' }, 'left out'),
          el('span', { class: 'n' }, `×${c.count}`)))
          : el('p', { class: 'muted', style: 'font-size:15px' }, 'No mistakes recorded. Try a faster start speed.')),
      el('div', { class: 'card' }, el('div', { class: 'card-head' }, el('h3', {}, 'Accuracy by speed')), speedBands(a.bands))),
    el('p', { class: 'footnote' }, `Based on ${a.answered.toLocaleString('en-GB')} answered items from ${plural(records.length, 'attempt')}. Characters need ${MIN_SAMPLES} copies before they’re ranked. A copy is instant when it’s correct and you type the first key within 1 second of the sound ending. Typing the rest and pressing Return don’t count. Characters copied correctly 90% of the time and instantly 80% get ⚡.`));
}

function charRow(s, needsWork) {
  const value = s.instantRate ?? s.accuracy ?? 0;
  let detail = s.timed ? `${s.instant} of ${s.timed} instant · ${pct(s.accuracy ?? 0)} correct` : `${s.correct} of ${s.sent} correct`;
  if (s.averageThinkMs != null) detail += ` · ${s.averageThinkMs} ms after the sound`;
  if (needsWork && s.mixUp) detail += s.mixUp.typed ? ` · often typed as ${s.mixUp.typed}` : ' · often left out';
  return el('div', { class: 'char-row' },
    el('span', { class: 'char-badge', style: `background:${accuracyColour(value, 0.22)}` }, s.c, s.isInstant ? el('span', { class: 'bolt' }, '⚡') : null),
    el('div', { class: 'info' },
      el('div', { class: 'top' }, el('span', { class: 'morse' }, morse(s.c)), el('b', { class: 'num', style: 'font-size:15px' }, `${pct(value)} ${s.instantRate != null ? 'instant' : 'correct'}`)),
      el('div', { class: 'meter' }, el('i', { style: `width:${Math.round(value * 100)}%;background:${accuracyColour(value)}` })),
      el('small', {}, detail)));
}

function cell(s) {
  const enough = s.sent >= MIN_SAMPLES;
  let help = s.sent ? `${s.c}: ${s.correct} of ${s.sent} correct` : `${s.c}: not sent yet`;
  if (s.sent && !enough) help += ' (not enough copies to rank)';
  if (s.timed) help += `, ${s.instant} instant`;
  if (s.averageThinkMs != null) help += `, ${s.averageThinkMs} ms after the sound on average`;
  if (s.mixUp) help += s.mixUp.typed ? `, often typed as ${s.mixUp.typed}` : ', often left out';
  return el('div', {
    class: 'cell', title: help, role: 'img', 'aria-label': help,
    style: enough ? `background:${accuracyColour(s.accuracy, 0.28)};border-color:${accuracyColour(s.accuracy, 0.5)}` : 'background:var(--surface-2)',
  }, el('b', {}, s.c), el('span', {}, enough && s.isInstant ? '⚡ ' : '', enough ? pct(s.accuracy ?? 0) : '—'));
}

function speedBands(bands) {
  if (!bands.length) return el('p', { class: 'muted', style: 'font-size:15px' }, 'Not enough data yet.');
  const W = 400, H = 190, L = 36, T = 8, B = 24;
  const bw = (W - L) / bands.length;
  const Y = (a) => T + (1 - a) * (H - T - B);
  const breakpoint = bands.find((b) => b.total >= 5 && b.correct / b.total < 0.5);
  return el('div', {},
    svg('svg', { class: 'chart', viewBox: `0 0 ${W} ${H}`, role: 'img', 'aria-label': 'Accuracy by speed' },
      [0, 0.5, 1].map((t) => [svg('line', { class: 'grid', x1: L, x2: W, y1: Y(t), y2: Y(t), 'stroke-dasharray': t === 0.5 ? '3 3' : null }),
        svg('text', { x: L - 6, y: Y(t) + 4, 'text-anchor': 'end' }, pct(t))]),
      bands.map((b, i) => {
        const acc = b.correct / b.total;
        return [svg('rect', { x: L + i * bw + bw * 0.15, y: Y(acc), width: bw * 0.7, height: Math.max(1, Y(0) - Y(acc)), rx: 4, fill: accuracyColour(acc) },
          svg('title', {}, `${speedValue(b.lowerCPM)}–${speedValue(b.upperCPM)} ${unit()}: ${b.correct} of ${b.total} (${pct(acc)})`)),
        svg('text', { x: L + i * bw + bw / 2, y: H - 6, 'text-anchor': 'middle' }, String(speedValue(b.lowerCPM)))];
      })),
    el('p', { class: 'note' }, breakpoint
      ? `Accuracy drops below half from about ${speed(breakpoint.lowerCPM)}. Start a little below that to build a solid base.`
      : 'You’re above 50% at every speed you’ve reached. Try starting faster.'));
}

// MARK: History

let historySort = 'date';
function renderHistory() {
  if (!history.length) {
    fill($('view'), el('div', { class: 'empty' }, el('b', {}, 'No history'), 'Every finished attempt is saved here, in this browser.'));
    return;
  }
  const sorters = {
    date: (a, b) => byDate(b, a),
    score: (a, b) => record.score(b) - record.score(a),
    peak: (a, b) => record.peak(b) - record.peak(a),
    source: (a, b) => a.source.localeCompare(b.source) || byDate(b, a),
  };
  const rows = [...history].sort(sorters[historySort]);
  fill($('view'),
    el('div', { class: 'toolbar' }, el('h2', { class: 'title', style: 'margin:0' }, 'History'), el('span', { class: 'spacer' }),
      el('select', { 'aria-label': 'Sort by', onchange: (e) => { historySort = e.target.value; render(); } },
        [['date', 'Newest first'], ['score', 'Highest score'], ['peak', 'Fastest peak'], ['source', 'By source']].map(([val, label]) =>
          el('option', { value: val, selected: val === historySort }, label))),
      el('button', { class: 'btn', type: 'button', onclick: exportCSV }, 'Export CSV')),
    el('div', { class: 'list' }, rows.map((r) => el('button', { class: 'row', type: 'button', onclick: () => openAttempt(r) },
      el('div', { class: 'main' }, el('div', {}, r.source),
        el('div', { class: 'sub num' }, `${utc(r.date)} · ${record.correct(r)}/${r.results.length} correct · peak ${speed(record.peak(r))}`)),
      el('span', { class: 'score' }, String(record.score(r))),
      el('span', { class: 'chev' }, '›')))));
}

let openRecord = null;
function openAttempt(rec) {
  openRecord = rec;
  const fixed = rec.config.stepPercent === 0;
  $('attemptTitle').textContent = `${record.score(rec)} points`;
  fill($('attemptBody'),
    el('p', { class: 'lede', style: 'margin:10px 4px 4px' }, `${rec.source} · ${utc(rec.date)}`),
    el('dl', { class: 'facts', style: 'margin:10px 4px 14px' },
      [['Correct', `${record.correct(rec)} of ${rec.results.length}`], ['Peak speed', speed(record.peak(rec))],
        ['Average speed', speed(record.average(rec))], [fixed ? 'Speed' : 'Start speed', speed(rec.config.startCPM)],
        ['Avg response (ms)', ms(record.response(rec))], ['Speed step', fixed ? 'Fixed speed' : `${rec.config.stepPercent}% per copy`]]
        .flatMap(([k, val]) => [el('dt', {}, k), el('dd', {}, val)])),
    el('div', { class: 'card' }, speedChart(rec)),
    el('div', { class: 'card', style: 'padding:6px 4px' }, resultsTable(rec)));
  $('attempt').showModal();
  $('attemptBody').scrollTop = 0;
}
$('deleteAttempt').addEventListener('click', () => {
  if (!openRecord || !confirm('Delete this attempt? This can’t be undone.')) return;
  history = history.filter((r) => r.id !== openRecord.id);
  saveHistory();
  $('attempt').close();
  render();
});

/// The Mac app's CSV columns (HistoryStore.csv).
function exportCSV() {
  track('history/export csv');
  const lines = ['date,source,callsigns,score,correct,peak_cpm,peak_wpm,average_cpm,start_cpm,average_response_ms'];
  for (const r of [...history].sort(byDate)) {
    const peak = record.peak(r);
    lines.push([r.date, `"${r.source.replaceAll('"', '""')}"`, r.results.length, record.score(r), record.correct(r),
      Math.round(peak), Math.round(peak / 5), Math.round(record.average(r)), Math.round(r.config.startCPM), record.response(r) ?? ''].join(','));
  }
  const a = el('a', { href: URL.createObjectURL(new Blob([lines.join('\n') + '\n'], { type: 'text/csv' })), download: 'QRQTrainer-history.csv' });
  document.body.append(a);
  a.click();
  a.remove();
  setTimeout(() => URL.revokeObjectURL(a.href), 1000);
}

// MARK: Characters sheet

let characterClasses = Object.keys(CLASSES);
function openCharacters(classes = Object.keys(CLASSES)) {
  characterClasses = classes;
  renderCharacters();
  $('characters').showModal();
}
function renderCharacters() {
  const enabled = new Set(settings.enabledCharacters);
  const apply = (chars, fn) => {
    for (const c of chars) if (fn(enabled.has(c))) enabled.add(c); else enabled.delete(c);
    settings.enabledCharacters = [...ALL_CHARACTERS].filter((c) => enabled.has(c)).join('');
    save();
    renderCharacters();
  };
  fill($('charactersForm'),
    el('p', { class: 'foot', style: 'margin:10px 6px 0;font-size:14px' }, 'Choose which characters the Letters, Numbers and Symbols modes (and their combinations) send. Each mode only uses its own rows, so Letters ignores numbers and symbols. Callsigns, Ham codes, Words and Needs work aren’t affected.'),
    characterClasses.map((key) => {
      const cls = CLASSES[key];
      const on = [...cls.chars].filter((c) => enabled.has(c)).length;
      return [el('div', { class: 'class-head' }, el('b', {}, cls.title), el('span', { class: 'muted num' }, `${on} of ${cls.chars.length}`),
        el('span', { class: 'acts' },
          el('button', { class: 'link-btn', type: 'button', onclick: () => apply(cls.chars, () => true) }, 'All'),
          el('button', { class: 'link-btn', type: 'button', onclick: () => apply(cls.chars, () => false) }, 'None'),
          el('button', { class: 'link-btn', type: 'button', onclick: () => apply(cls.chars, (x) => !x) }, 'Invert'))),
      el('div', { class: 'chips' }, [...cls.chars].map((c) => el('button', {
        class: 'chip', type: 'button', 'aria-pressed': String(enabled.has(c)), 'aria-label': `Character ${c}`,
        onclick: () => apply([c], (x) => !x),
      }, c)))];
    }));
}
$('characters').addEventListener('close', () => render());

// MARK: Settings sheet

function field(label, control, { sub, disabled } = {}) {
  return el('div', { class: `field${disabled ? ' disabled' : ''}` }, el('div', { class: 'label' }, label, sub ? el('small', {}, sub) : null), control);
}
function sliderField(label, key, min, max, step, format, onInput) {
  const out = el('output', {}, format(settings[key]));
  return el('div', { class: 'field slider' }, el('div', { class: 'label' }, label), out,
    el('input', { type: 'range', min, max, step, value: settings[key], 'aria-label': label,
      oninput: (e) => { settings[key] = +e.target.value; out.textContent = format(settings[key]); save(); onInput?.(); } }));
}
function selectField(label, value, options, onChange, disabled = false) {
  return field(label, el('select', { 'aria-label': label, disabled, onchange: (e) => onChange(e.target.value) },
    options.map(([val, text]) => el('option', { value: val, selected: String(val) === String(value) }, text))));
}

function renderSettings() {
  const f = $('settingsForm');
  const keepScroll = f.scrollTop;
  const rerender = () => { renderSettings(); };
  const gen = engine ? describe().generatedExamples : [];
  const startCPM = settings.startCPM;
  const farnsFoot = 'Sends each character at full speed but stretches the gaps between characters and words, so you learn the sound of fast characters with more time to think.'
    + (settings.farnsworth ? ` At your start speed, characters are sent at ${speed(startCPM)} with an overall speed of ${speed(startCPM * settings.farnsworthPercent / 100)}.` : '')
    + ' Attempts with Farnsworth spacing are scored separately.';
  fill(f,
    el('div', { class: 'section-title' }, 'Training'),
    el('div', { class: 'group' },
      selectField('Show speed as', settings.showWPM, [[false, 'CPM'], [true, 'WPM (PARIS)']],
        (val) => { settings.showWPM = val === 'true'; save(); rerender(); }),
      field('Fixed speed', toggle(settings.fixedSpeed, (val) => { settings.fixedSpeed = val; save(); rerender(); }, 'Fixed speed')),
      field('Speed change per copy', stepper(settings.stepPercent, 1, 10, (val) => { settings.stepPercent = val; save(); rerender(); }, 0.5, (x) => `${x}%`), { disabled: settings.fixedSpeed })),
    el('p', { class: 'foot' }, settings.fixedSpeed ? 'Every item is sent at the start speed. Fixed-speed attempts are scored separately.'
      : 'A correct copy raises the speed by this percentage, a miss lowers it. Repeats don’t raise it.'),
    el('div', { class: 'group' },
      field('Farnsworth spacing', toggle(settings.farnsworth, (val) => { settings.farnsworth = val; save(); rerender(); }, 'Farnsworth spacing')),
      settings.farnsworth ? sliderField('Overall speed', 'farnsworthPercent', 20, 95, 5, (x) => `${x}%`) : null),
    el('p', { class: 'foot' }, farnsFoot),
    el('div', { class: 'group' }, sliderField('Pause before next item', 'pauseMs', 0, 2000, 50, (x) => `${x} ms`)),

    el('div', { class: 'section-title' }, 'Audio'),
    el('div', { class: 'group' },
      sliderField('Pitch', 'pitch', 300, 1200, 10, (x) => `${x} Hz`),
      field('Vary pitch for each item', toggle(settings.randomPitch, (val) => { settings.randomPitch = val; save(); rerender(); }, 'Vary pitch for each item')),
      settings.randomPitch ? sliderField('Variation', 'pitchSpread', 10, 300, 10, (x) => `± ${x} Hz`) : null,
      sliderField('Volume', 'volume', 0.05, 1, 0.05, (x) => pct(x)),
      sliderField('Edge shaping', 'riseMs', 1, 10, 0.5, (x) => `${x} ms`),
      el('div', { class: 'field' }, el('button', { class: 'link-btn', type: 'button', 'data-test-tone': 'Play test tone', onclick: toggleTestTone }, testTonePlaying ? 'Stop' : 'Play test tone'))),
    el('p', { class: 'foot' }, 'Softer edges sound cleaner; they are shortened automatically at very high speeds so dits stay crisp.'),

    el('div', { class: 'section-title' }, 'Characters'),
    el('div', { class: 'group' }, el('div', { class: 'field' },
      el('button', { class: 'link-btn', type: 'button', onclick: () => openCharacters() }, `Choose characters… (${settings.enabledCharacters.length} of ${ALL_CHARACTERS.length})`))),
    el('p', { class: 'foot' }, 'Which characters the Letters, Numbers and Symbols modes send.'),

    el('div', { class: 'section-title', id: 'callsignSettings' }, 'Callsigns'),
    el('div', { class: 'group' },
      // Always available: choosing the imported list before there is one opens the file picker, and the source
      // switches over once a list has loaded (importList).
      selectField('Source', settings.useImported && importedCount ? 'imported' : 'generated',
        [['generated', 'Generated callsigns'], ['imported', importedCount ? 'Imported list' : 'Imported list…']],
        (val) => {
          if (val === 'imported' && !importedCount) { rerender(); $('listFile').click(); return; }
          settings.useImported = val === 'imported'; save(); rerender();
        }),
      importedCount ? field(importedList.name, el('span', { class: 'value' }, `${importedCount.toLocaleString('en-GB')} callsigns`)) : null,
      el('div', { class: 'field' },
        el('button', { class: 'link-btn', type: 'button', onclick: () => $('listFile').click() }, importedCount ? 'Replace the list…' : 'Import a callsign list…'),
        importedCount ? el('button', { class: 'link-btn', type: 'button', style: 'color:var(--danger);width:auto', onclick: removeList }, 'Remove') : null)),
    el('p', { class: 'foot' }, 'Real callsigns from a file such as Super Check Partial’s MASTER.SCP (from supercheckpartial.com) feel most like on-air copying. One or more calls per line; lines starting with # are skipped.'),
    el('div', { class: 'group' },
      field('Portable / mobile (/P, /M)', stepper(settings.portablePercent, 0, 50, (val) => { settings.portablePercent = val; save(); rerender(); }, 5, (x) => `${x}%`)),
      field('Foreign prefix (EA8/…)', stepper(settings.prefixedPercent, 0, 50, (val) => { settings.prefixedPercent = val; save(); rerender(); }, 5, (x) => `${x}%`)),
      field('Examples', el('span', { class: 'value mono', style: 'text-align:right;white-space:normal' }, gen.join('  ')))),
    el('p', { class: 'foot' }, 'For generated callsigns.'),

    el('div', { class: 'section-title' }, 'Appearance'),
    el('div', { class: 'group' }, selectField('Appearance', appearance, [['system', 'Same as the device'], ['light', 'Light'], ['dark', 'Dark']],
      (val) => { appearance = val; store.set('appearance', val); applyAppearance(); })),
    el('div', { class: 'help in-sheet' }, $('aboutTemplate').content.cloneNode(true)),
    el('input', { type: 'file', id: 'listFile', accept: '.scp,.txt,text/plain', hidden: true, onchange: importList }));
  f.scrollTop = keepScroll;
}

function openSettings(section) {
  renderSettings();
  $('settings').showModal();
  if (section === 'callsigns') $('callsignSettings').scrollIntoView();
  else $('settingsForm').scrollTop = 0;
}
$('settingsBtn').addEventListener('click', () => openSettings());
$('settings').addEventListener('close', () => { stopTestTone(); render(); });
for (const d of document.querySelectorAll('dialog')) {
  d.addEventListener('click', (e) => { if (e.target.closest('[data-close]') || e.target === d) d.close(); });
}

async function importList(e) {
  const file = e.target.files?.[0];
  e.target.value = '';
  if (!file) return;
  const answer = engine.call('setList', { text: await file.text() });
  if (!answer.count) {
    engine.call('setList', { text: importedList?.text ?? '' });
    toast('The file doesn’t contain any recognisable callsigns.');
    return;
  }
  importedList = { name: file.name, text: answer.text };
  importedCount = answer.count;
  track('callsigns/imported a list');
  if (!store.set('list', importedList)) toast('The list is too big to keep in this browser; it will be used until you close the page.');
  settings.useImported = true;
  save();
  toast(`Imported ${answer.count.toLocaleString('en-GB')} callsigns.`);
  renderSettings();
}
function removeList() {
  importedList = null;
  importedCount = 0;
  store.remove('list');
  engine.call('setList', { text: '' });
  settings.useImported = false;
  save();
  renderSettings();
}

let toastTimer = 0;
function toast(message) {
  document.querySelector('.toast')?.remove();
  const t = el('div', { class: 'toast', role: 'status' }, message);
  document.body.append(t);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => t.remove(), 3500);
}

// MARK: Keys: ⌘↩ starts, ↩ submits, F6 or ⌘R repeats, esc ends the attempt

document.addEventListener('keydown', (e) => {
  if (document.querySelector('dialog[open]')) return;
  const mod = e.metaKey || e.ctrlKey;
  if (trainer.phase === 'running') {
    if (e.key === 'F6' || (mod && e.key.toLowerCase() === 'r')) { e.preventDefault(); repeatCurrent(); }
    else if (e.key === 'Escape') { e.preventDefault(); abort(); }
    else if (document.activeElement !== copying.entry && e.key.length === 1 && !mod) copying.entry?.focus();
  } else if (mod && e.key === 'Enter' && (view === 'train')) {
    e.preventDefault();
    start();
  }
});

// MARK: Start-up

countVisit();
engineReady.then((e) => {
  engine = e;
  morseCodes = engine.call('codes');
  if (importedList?.text) importedCount = engine.call('setList', { text: importedList.text }).count;
  render();
}).catch((error) => {
  fill($('view'), el('div', { class: 'empty' }, el('b', {}, 'QRQ Trainer couldn’t start'), String(error?.message ?? error)));
});

import { useEffect, useState } from 'preact/hooks';
import { pop } from './nav.js';
import { GROUPS, groupTotals } from './lib/muscles.js';
import { capitalize, SET_KINDS } from './lib/format.js';

export function TopBar({ title, left, right, onBack }) {
  return (
    <div class="topbar">
      <div class="side">{left ?? <button class="link" onClick={onBack || (() => pop())}>‹ Back</button>}</div>
      <div class="title">{title}</div>
      <div class="side right">{right}</div>
    </div>
  );
}

export function Page({ children }) {
  return <div class="overlay"><div class="screen">{children}</div></div>;
}

export function BottomBar({ children }) {
  return <div class="bottom-bar"><div>{children}</div></div>;
}

export function Thumb({ src, name, lg, onClick }) {
  const [failed, setFailed] = useState(false);
  if (!src || failed) return <div class={`thumb ph ${lg ? 'lg' : ''}`} onClick={onClick}>{(name || '?').charAt(0).toUpperCase()}</div>;
  return <img class={`thumb ${lg ? 'lg' : ''}`} src={src} alt={name} loading="lazy" onError={() => setFailed(true)} onClick={onClick} />;
}

export function MuscleChips({ muscles, secondary = [] }) {
  return (
    <div class="gap8">
      {muscles.map((m) => <span class="chip" key={m}><span class="dot" style={{ background: GROUPS[groupOfSafe(m)].color }} />{capitalize(m)}</span>)}
      {secondary.map((m) => <span class="chip faint" key={`s${m}`}>{capitalize(m)}</span>)}
    </div>
  );
}

import { groupOf } from './lib/muscles.js';
const groupOfSafe = (m) => groupOf(m);

/** Muscle overview: totals per group plus each muscle's share. */
export function MuscleOverview({ loads }) {
  if (!loads.length) return <p class="muted small">Add exercises to see which muscles you'll train.</p>;
  const groups = groupTotals(loads);
  const max = Math.max(...groups.map((g) => g.score));
  const maxM = Math.max(...loads.map((l) => l.score));
  return (
    <div>
      {groups.map((g) => (
        <div key={g.group} class="mb8">
          <div class="row between small"><span class="bold">{GROUPS[g.group].label}</span><span class="muted">{fmtScore(g.score)} sets</span></div>
          <div class="bar"><div style={{ width: `${(g.score / max) * 100}%`, background: GROUPS[g.group].color }} /></div>
        </div>
      ))}
      <details class="mt8">
        <summary>Every muscle ({loads.length})</summary>
        {loads.map((l) => (
          <div key={l.muscle} class="row small" style={{ padding: '4px 0' }}>
            <span class="dot" style={{ width: 8, height: 8, borderRadius: 4, background: GROUPS[l.group].color }} />
            <span class="grow">{capitalize(l.muscle)}</span>
            <span class="muted">{l.primary ? `${fmtScore(l.primary)} main` : ''}{l.primary && l.secondary ? ' · ' : ''}{l.secondary ? `${fmtScore(l.secondary)} assist` : ''}</span>
            <div class="bar" style={{ width: 60 }}><div style={{ width: `${(l.score / maxM) * 100}%`, background: GROUPS[l.group].color }} /></div>
          </div>
        ))}
      </details>
    </div>
  );
}
const fmtScore = (n) => (Number.isInteger(n) ? n : n.toFixed(1));

export function Stepper({ value, onChange, step = 1, min = 0, unit, decimals = false, width }) {
  const [text, setText] = useState(String(value));
  useEffect(() => setText(String(value)), [value]);
  const commit = (t) => {
    const n = decimals ? parseFloat(String(t).replace(',', '.')) : parseInt(t, 10);
    if (Number.isFinite(n)) onChange(Math.max(min, Math.round(n * 100) / 100)); else setText(String(value));
  };
  return (
    <div class="stepper">
      <button onClick={() => onChange(Math.max(min, Math.round((value - step) * 100) / 100))} aria-label="minus">−</button>
      <input inputMode={decimals ? 'decimal' : 'numeric'} value={text} style={width ? { width } : null}
        onInput={(e) => setText(e.currentTarget.value)} onBlur={(e) => commit(e.currentTarget.value)}
        onKeyDown={(e) => e.key === 'Enter' && e.currentTarget.blur()} />
      {unit && <span class="unit">{unit}</span>}
      <button onClick={() => onChange(Math.round((value + step) * 100) / 100)} aria-label="plus">+</button>
    </div>
  );
}

export function KindBadge({ kind, index }) {
  return <div class={`badge ${kind}`}>{kind === 'normal' ? index : SET_KINDS[kind].badge}</div>;
}

/** Numbers normal sets 1..n and gives warm-up/drop sets their letter. */
export function setNumbers(sets) {
  let n = 0;
  return sets.map((s) => (s.kind === 'normal' ? ++n : 0));
}

export function Toggle({ label, sub, on, onChange }) {
  return (
    <div class="toggle">
      <div class="col"><span>{label}</span>{sub && <span class="small muted">{sub}</span>}</div>
      <button class={`switch ${on ? 'on' : ''}`} role="switch" aria-checked={on} onClick={() => onChange(!on)} />
    </div>
  );
}

export function Segmented({ options, value, onChange }) {
  return (
    <div class="segmented">
      {options.map(([v, label]) => <button key={v} class={v === value ? 'on' : ''} onClick={() => onChange(v)}>{label}</button>)}
    </div>
  );
}

export function Sheet({ children, onClose }) {
  return (
    <div class="sheet-bg" onClick={(e) => e.target === e.currentTarget && onClose?.()}>
      <div class="sheet">{children}</div>
    </div>
  );
}

export function useNow(intervalMs = 1000) {
  const [now, setNow] = useState(Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), intervalMs);
    const vis = () => setNow(Date.now());
    document.addEventListener('visibilitychange', vis);
    return () => { clearInterval(id); document.removeEventListener('visibilitychange', vis); };
  }, [intervalMs]);
  return now;
}

export function Ring({ progress, size = 64, stroke = 6, color = '#0a1730', track = 'rgba(10,23,48,0.15)', children }) {
  const r = (size - stroke) / 2;
  const c = 2 * Math.PI * r;
  return (
    <svg class="ring" width={size} height={size} viewBox={`0 0 ${size} ${size}`}>
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={track} stroke-width={stroke} />
      <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke={color} stroke-width={stroke} stroke-linecap="round"
        stroke-dasharray={c} stroke-dashoffset={c * (1 - Math.min(1, Math.max(0, progress)))} transform={`rotate(-90 ${size / 2} ${size / 2})`} />
      {children}
    </svg>
  );
}

export function Icon({ name }) {
  const p = {
    workouts: 'M6.5 6.5v11M17.5 6.5v11M3 9v6M21 9v6M6.5 12h11',
    progress: 'M4 20V10M10 20V4M16 20v-7M22 20H2',
    history: 'M12 8v4l3 2M3.05 11a9 9 0 1 1 .5 4M3 4v5h5',
    settings: 'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6zM19.4 15a1.7 1.7 0 0 0 .3 1.8l.1.1a2 2 0 1 1-2.8 2.8l-.1-.1a1.7 1.7 0 0 0-1.8-.3 1.7 1.7 0 0 0-1 1.5V21a2 2 0 1 1-4 0v-.1a1.7 1.7 0 0 0-1.1-1.5 1.7 1.7 0 0 0-1.8.3l-.1.1a2 2 0 1 1-2.8-2.8l.1-.1a1.7 1.7 0 0 0 .3-1.8 1.7 1.7 0 0 0-1.5-1H3a2 2 0 1 1 0-4h.1a1.7 1.7 0 0 0 1.5-1.1 1.7 1.7 0 0 0-.3-1.8l-.1-.1a2 2 0 1 1 2.8-2.8l.1.1a1.7 1.7 0 0 0 1.8.3H9a1.7 1.7 0 0 0 1-1.5V3a2 2 0 1 1 4 0v.1a1.7 1.7 0 0 0 1 1.5 1.7 1.7 0 0 0 1.8-.3l.1-.1a2 2 0 1 1 2.8 2.8l-.1.1a1.7 1.7 0 0 0-.3 1.8V9a1.7 1.7 0 0 0 1.5 1H21a2 2 0 1 1 0 4h-.1a1.7 1.7 0 0 0-1.5 1z',
  }[name];
  return <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d={p} /></svg>;
}

import { useEffect, useState } from 'preact/hooks';
import { pop } from './nav.js';
import { GROUPS, groupTotals } from './lib/muscles.js';
import { capitalize, SET_KINDS } from './lib/format.js';
import { bodyHeat, shapes, smoothPath, SILHOUETTE, REGION_LABELS } from './lib/bodymap.js';

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

/** Where to try loading an exercise GIF from, in order: the saved link (upgraded
 * to https), then our cached proxy, which looks up the exercise's current link by id. */
export function gifSources(src, id) {
  const list = [];
  let direct = typeof src === 'string' ? src.trim() : '';
  if (direct.startsWith('//')) direct = `https:${direct}`;
  if (direct.startsWith('http://')) direct = `https://${direct.slice(7)}`;
  if (direct.startsWith('https://')) list.push(direct);
  if (id && !String(id).startsWith('custom-')) list.push(`/api/gif?id=${encodeURIComponent(id)}`);
  return list;
}

/** Exercise GIF. Falls back to the proxy when the saved link fails, and a failed
 * tile can be tapped to try again. */
export function Thumb({ src, id, name, lg, onClick }) {
  const sources = gifSources(src, id);
  const key = `${src}|${id}`;
  // Derived from the props (not reset in an effect) so a fast failure can't be undone.
  const [saved, setSaved] = useState({ key, index: 0, attempt: 0 });
  const st = saved.key === key ? saved : { key, index: 0, attempt: 0 };
  const cls = `thumb ${lg ? 'lg' : ''}`;
  const current = sources[st.index];
  if (!current) {
    const canRetry = sources.length > 0;
    return (
      <div class={`${cls} ph`} title={canRetry ? 'Tap to retry' : undefined}
        onClick={(e) => { if (canRetry) { e.stopPropagation(); setSaved({ key, index: 0, attempt: st.attempt + 1 }); } else onClick?.(e); }}>
        {(name || '?').charAt(0).toUpperCase()}{canRetry && <span class="retry">↻</span>}
      </div>
    );
  }
  const url = st.attempt ? `${current}${current.includes('?') ? '&' : '?'}retry=${st.attempt}` : current;
  return <img key={url} class={cls} src={url} alt="" loading={lg ? 'eager' : 'lazy'} decoding="async"
    onError={() => setSaved({ ...st, index: st.index + 1 })} onClick={onClick} />;
}

/** Front and back body figures with the worked muscles highlighted. */
export function BodyMap({ loads }) {
  const heat = bodyHeat(loads);
  const fill = (region) => {
    const h = region && heat[region];
    if (!region) return 'var(--muscle-idle-body)';
    if (h?.primary > 0) return `rgba(255, 85, 63, ${0.55 + 0.45 * h.share})`;
    if (h?.secondary > 0) return `rgba(255, 168, 74, ${0.55 + 0.35 * h.share})`;
    return 'var(--muscle-idle)';
  };
  const worked = Object.keys(heat).filter((r) => heat[r].score > 0).sort((a, b) => heat[b].score - heat[a].score);
  const label = worked.length ? `Body map. Worked: ${worked.map((r) => REGION_LABELS[r]).join(', ')}` : 'Body map: no muscles yet';
  return (
    <div class="bodymap" role="img" aria-label={label}>
      <div class="figures">
        {['front', 'back'].map((side) => (
          <figure key={side}>
            <svg viewBox="0 0 200 420">
              <path d={smoothPath(SILHOUETTE)} fill="var(--muscle-silhouette)" />
              {shapes(side).map((s, i) => (s.ellipse
                ? <ellipse key={i} cx={s.ellipse[0]} cy={s.ellipse[1]} rx={s.ellipse[2]} ry={s.ellipse[3]} fill={fill(null)} stroke="var(--bg)" stroke-width="1.6" />
                : <path key={i} d={s.d} fill={fill(s.region)} stroke="var(--bg)" stroke-width="1.6" stroke-linejoin="round" />))}
            </svg>
            <figcaption>{side === 'front' ? 'Front' : 'Back'}</figcaption>
          </figure>
        ))}
      </div>
      <div class="legend">
        <span><i style={{ background: 'var(--muscle-hot)' }} />Main target</span>
        <span><i style={{ background: 'var(--muscle-warm)' }} />Also worked</span>
        <span><i style={{ background: 'var(--muscle-idle)' }} />Not worked</span>
      </div>
    </div>
  );
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

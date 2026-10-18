export const uid = () =>
  (crypto.randomUUID ? crypto.randomUUID() : Date.now().toString(36) + Math.random().toString(36).slice(2));

export const SET_KINDS = {
  warmup: { label: 'Warm-up', badge: 'W' },
  normal: { label: 'Normal', badge: '' },
  drop: { label: 'Drop set', badge: 'D' },
};

export function weight(kg) {
  if (!kg) return 'BW';
  const r = Math.round(kg * 100) / 100;
  return Number.isInteger(r) ? `${r} kg` : `${r.toFixed(1)} kg`;
}

export function num(v) {
  return Number.isInteger(v) ? String(v) : v.toFixed(1);
}

export function duration(seconds) {
  const t = Math.max(0, Math.round(seconds));
  const h = Math.floor(t / 3600), m = Math.floor((t % 3600) / 60), s = t % 60;
  const pad = (n) => String(n).padStart(2, '0');
  return h > 0 ? `${h}:${pad(m)}:${pad(s)}` : `${m}:${pad(s)}`;
}

export function shortDuration(seconds) {
  const minutes = Math.round(seconds / 60);
  return minutes >= 60 ? `${Math.floor(minutes / 60)}h ${minutes % 60}m` : `${minutes} min`;
}

export function rest(seconds) {
  if (seconds < 60) return `${seconds}s`;
  if (seconds % 60 === 0) return `${seconds / 60} min`;
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`;
}

export function volume(kg) {
  return kg >= 10000 ? `${(kg / 1000).toFixed(1)} t` : `${Math.round(kg)} kg`;
}

export function capitalize(s = '') {
  return s.charAt(0).toUpperCase() + s.slice(1);
}

export function dateLabel(ms, opts = { weekday: 'short', day: 'numeric', month: 'short' }) {
  return new Date(ms).toLocaleDateString(undefined, opts);
}

/** "3 × 12 @ 30 kg · 1W · 1D" summary of a planned exercise. */
export function setSummary(plan) {
  const working = plan.sets.filter((s) => s.kind === 'normal');
  if (!working.length) return `${plan.sets.length} sets`;
  const sameReps = working.every((s) => s.reps === working[0].reps);
  const maxW = Math.max(...working.map((s) => s.weight));
  let text = sameReps ? `${working.length} × ${working[0].reps}` : `${working.length} sets`;
  if (maxW > 0) text += ` @ ${weight(maxW)}`;
  const w = plan.sets.filter((s) => s.kind === 'warmup').length;
  const d = plan.sets.filter((s) => s.kind === 'drop').length;
  if (w) text += ` · ${w}W`;
  if (d) text += ` · ${d}D`;
  return text;
}

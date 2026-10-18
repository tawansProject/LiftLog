import { doneWorkingSets, hasProgress } from './models.js';

export const GROUPS = {
  chest: { label: 'Chest', color: '#ff6b6b' },
  back: { label: 'Back', color: '#4d8dff' },
  shoulders: { label: 'Shoulders', color: '#ffa94d' },
  arms: { label: 'Arms', color: '#b197fc' },
  core: { label: 'Core', color: '#ffd43b' },
  legs: { label: 'Legs', color: '#51cf66' },
  cardio: { label: 'Cardio', color: '#f783ac' },
  other: { label: 'Other', color: '#adb5bd' },
};

const MAP = {
  chest: ['pectorals', 'serratus anterior', 'chest'],
  back: ['latissimus dorsi', 'lats', 'upper back', 'rhomboids', 'trapezius', 'traps', 'erector spinae', 'back',
    'levator scapulae', 'lower back', 'spine'],
  shoulders: ['deltoids', 'delts', 'rear deltoids', 'rotator cuff', 'shoulders'],
  arms: ['biceps', 'triceps', 'brachialis', 'forearms', 'wrist flexors', 'wrist extensors', 'grip muscles', 'wrists', 'hands'],
  core: ['abdominals', 'abs', 'obliques', 'core', 'hip flexors'],
  legs: ['quadriceps', 'quads', 'hamstrings', 'glutes', 'calves', 'adductors', 'abductors', 'soleus', 'tibialis anterior',
    'ankles', 'ankle stabilizers', 'feet', 'groin', 'inner thighs', 'shins'],
  cardio: ['cardiovascular system'],
};

export function groupOf(muscle) {
  const m = muscle.toLowerCase();
  for (const [g, list] of Object.entries(MAP)) if (list.includes(m)) return g;
  return 'other';
}

/** Work per muscle: sets count fully for target muscles, half for secondary. */
export function loads(inputs) {
  const table = {};
  const get = (m) => (table[m] ||= { muscle: m, group: groupOf(m), primary: 0, secondary: 0 });
  for (const ex of inputs) {
    const sets = Math.max(ex.sets, 1);
    for (const m of ex.target) get(m).primary += sets;
    for (const m of ex.secondary) if (!ex.target.includes(m)) get(m).secondary += sets;
  }
  return Object.values(table)
    .map((l) => ({ ...l, score: l.primary + l.secondary * 0.5 }))
    .sort((a, b) => b.score - a.score);
}

export const loadsPlanned = (planned) =>
  loads(planned.map((p) => ({ target: p.targetMuscles, secondary: p.secondaryMuscles, sets: p.sets.filter((s) => s.kind === 'normal').length })));

export const loadsLogged = (logged) =>
  loads(logged.filter(hasProgress).map((e) => ({
    target: e.targetMuscles, secondary: e.secondaryMuscles,
    sets: doneWorkingSets(e).length + e.sets.filter((s) => s.kind === 'drop' && s.isDone).length,
  })));

export function groupTotals(ls) {
  const t = {};
  for (const l of ls) t[l.group] = (t[l.group] || 0) + l.score;
  return Object.entries(t).map(([group, score]) => ({ group, score })).sort((a, b) => b.score - a.score);
}

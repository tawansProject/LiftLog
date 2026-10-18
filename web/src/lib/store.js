import { useEffect, useState } from 'preact/hooks';
import { uid } from './format.js';
import { loggedFromPlanned, asPlanned, hasProgress, isFinished } from './models.js';
import { lastLogWithDate, prefill } from './history.js';
import { applyToSets, increment, roundTo } from './progression.js';
import { estimateCalories } from './calories.js';
import * as push from './push.js';

const KEY = 'liftlog.v1';

export const DEFAULT_SETTINGS = {
  restBetweenSets: 90,
  restAfterExercise: 120,
  weeklyGoal: 3,
  bodyWeightKg: 70,
  age: 30,
  sex: 'male',
  updateTemplateAfterWorkout: true,
  restAlerts: true,
  keepAwake: true,
  sound: true,
  showGifInWorkout: true,
};

function load() {
  try {
    const raw = JSON.parse(localStorage.getItem(KEY));
    if (raw) return { templates: [], records: [], exerciseCache: {}, active: null, ...raw, settings: { ...DEFAULT_SETTINGS, ...raw.settings } };
  } catch { /* fall through to a fresh state */ }
  return { templates: [], records: [], exerciseCache: {}, active: null, settings: { ...DEFAULT_SETTINGS }, pushSubscription: null };
}

let state = load();
const listeners = new Set();

function save() {
  try { localStorage.setItem(KEY, JSON.stringify(state)); } catch (e) { console.warn('Could not save', e); }
}

export function getState() { return state; }

export function setState(patch) {
  state = { ...state, ...(typeof patch === 'function' ? patch(state) : patch) };
  save();
  listeners.forEach((l) => l(state));
}

export function useStore() {
  const [s, set] = useState(state);
  useEffect(() => { listeners.add(set); set(state); return () => listeners.delete(set); }, []);
  return s;
}

// MARK: Settings, cache, backup

export const updateSettings = (patch) => setState((s) => ({ settings: { ...s.settings, ...patch } }));

export function cacheExercise(ex) {
  setState((s) => ({ exerciseCache: { ...s.exerciseCache, [ex.exerciseId]: ex } }));
}

export function exportBackup() {
  const { templates, records, settings, exerciseCache } = state;
  return JSON.stringify({ app: 'LiftLog', version: 1, exportedAt: Date.now(), templates, records, settings, exerciseCache }, null, 1);
}

export function importBackup(text) {
  const data = JSON.parse(text);
  if (!Array.isArray(data.templates) || !Array.isArray(data.records)) throw new Error('This file is not a LiftLog backup.');
  setState({
    templates: data.templates,
    records: data.records,
    exerciseCache: data.exerciseCache || {},
    settings: { ...DEFAULT_SETTINGS, ...data.settings },
  });
}

// MARK: Templates

export function saveTemplate(t) {
  const now = Date.now();
  setState((s) => {
    const exists = s.templates.some((x) => x.id === t.id);
    const next = { ...t, updatedAt: now, createdAt: t.createdAt || now };
    return { templates: exists ? s.templates.map((x) => (x.id === t.id ? next : x)) : [...s.templates, next] };
  });
}

export const deleteTemplate = (id) => setState((s) => ({ templates: s.templates.filter((t) => t.id !== id) }));

export function duplicateTemplate(id) {
  const t = state.templates.find((x) => x.id === id);
  if (!t) return;
  saveTemplate({ ...structuredClone(t), id: uid(), name: `${t.name} copy`, createdAt: null });
}

export const prefillFor = (ex) => prefill(ex, state.records, state.templates, state.settings);

export const deleteRecord = (id) => setState((s) => ({ records: s.records.filter((r) => r.id !== id) }));

export function updateRecordExercise(recordId, exId, patch) {
  setState((s) => ({
    records: s.records.map((r) => (r.id !== recordId ? r : {
      ...r, exercises: r.exercises.map((e) => (e.id === exId ? { ...e, ...patch } : e)),
    })),
  }));
}

export function updateRecordCalories(recordId, { watchCalories, avgHeartRate }) {
  setState((s) => ({
    records: s.records.map((r) => {
      if (r.id !== recordId) return r;
      const est = estimateCalories({
        minutes: r.duration / 60, weightKg: s.settings.bodyWeightKg, age: s.settings.age, sex: s.settings.sex,
        watchCalories, avgHeartRate,
      });
      return { ...r, watchCalories, avgHeartRate, calories: est.kcal, caloriesSource: est.source };
    }),
  }));
}

// MARK: Live workout

function mutate(fn) {
  if (!state.active) return;
  const w = structuredClone(state.active);
  fn(w);
  setState({ active: w });
}

const isResting = (w) => w.restEndsAt != null && w.restEndsAt > Date.now();
const nextSetIndex = (e) => e.sets.findIndex((s) => !s.isDone);

function nextPendingIndex(w, ex) {
  const order = [...w.exercises.keys()].slice(ex + 1).concat([...w.exercises.keys()].slice(0, ex));
  const i = order.find((k) => w.exercises[k].status === 'pending');
  return i ?? null;
}

/** First exercise with sets done but no effort rating yet. */
export const unratedIndex = (w) => {
  const i = w.exercises.findIndex((e) => e.status === 'pending' && hasProgress(e));
  return i < 0 ? null : i;
};

/** Starts a workout. Exercises with a newer record elsewhere start from that record. */
export function startWorkout(name, templateId, items) {
  const template = state.templates.find((t) => t.id === templateId);
  const plans = items.map((p) => {
    const last = lastLogWithDate(p.exerciseId, state.records);
    if (template && last && last.date > template.updatedAt) {
      return { ...asPlanned(last.log), restBetweenSets: p.restBetweenSets, restAfterExercise: p.restAfterExercise };
    }
    return p;
  });
  setState({
    active: {
      id: uid(), name, templateId: templateId || null, startedAt: Date.now(),
      exercises: plans.map(loggedFromPlanned), currentIndex: 0,
      restEndsAt: null, restTotal: 0, restBetweenExercises: false, effortPendingIndex: null, finishAfterRating: false,
    },
    lastFinishedId: null,
  });
}

/** Quick session: starts right away with no plan. Exercises are added while
 * training; it's saved as a session when finished (and can be kept as a plan). */
export function startQuickWorkout() {
  startWorkout('Quick session', null, []);
}

/** Turns a finished quick session into a reusable workout plan and links it. */
export function saveRecordAsPlan(recordId, name) {
  const r = state.records.find((x) => x.id === recordId);
  if (!r) return null;
  const items = r.exercises.filter(hasProgress).map(asPlanned);
  if (!items.length) return null;
  const id = uid();
  const now = Date.now();
  setState((s) => ({
    templates: [...s.templates, { id, name, items, createdAt: now, updatedAt: now }],
    records: s.records.map((x) => (x.id === recordId ? { ...x, templateId: id } : x)),
  }));
  return id;
}

/** The exercise the next set belongs to: the current one if it has sets left,
 * otherwise the next pending exercise. */
export function upNextExercise(w = state.active) {
  if (!w) return null;
  const cur = w.exercises[w.currentIndex];
  if (cur && cur.status === 'pending' && nextSetIndex(cur) >= 0) return cur;
  const n = nextPendingIndex(w, w.currentIndex);
  return n == null ? null : w.exercises[n];
}

export function nextUpDescription(w = state.active) {
  if (!w) return null;
  const cur = w.exercises[w.currentIndex];
  if (cur && cur.status === 'pending') {
    const i = nextSetIndex(cur);
    if (i >= 0) {
      const s = cur.sets[i];
      return `${cur.name}: set ${i + 1} of ${cur.sets.length}, ${s.reps} reps${s.weight ? ` @ ${s.weight} kg` : ''}`;
    }
  }
  const n = nextPendingIndex(w, w.currentIndex);
  if (n != null) {
    const e = w.exercises[n];
    const s = e.sets[Math.max(0, nextSetIndex(e))];
    return `Next: ${e.name}${s ? `, ${s.reps} reps${s.weight ? ` @ ${s.weight} kg` : ''}` : ''}`;
  }
  return null;
}

export function startRest(seconds, betweenExercises) {
  if (seconds <= 0) return skipRest();
  const end = Date.now() + seconds * 1000;
  mutate((w) => { w.restEndsAt = end; w.restTotal = seconds; w.restBetweenExercises = betweenExercises; });
  scheduleAlert(end, betweenExercises);
}

function scheduleAlert(end, betweenExercises) {
  if (!state.settings.restAlerts || !state.pushSubscription) return;
  const title = betweenExercises ? 'Rest over: next exercise' : 'Rest over: next set';
  push.scheduleRest(state.pushSubscription, end, title, nextUpDescription() || 'Time to lift.');
}

export function addRest(seconds) {
  const w = state.active;
  if (!w) return;
  const resting = isResting(w);
  const end = (resting ? w.restEndsAt : Date.now()) + seconds * 1000;
  mutate((x) => { x.restTotal = resting ? x.restTotal + seconds : seconds; x.restEndsAt = end; });
  scheduleAlert(end, w.restBetweenExercises);
}

export function skipRest() {
  push.cancelRest();
  if (state.active?.restEndsAt != null) mutate((w) => { w.restEndsAt = null; });
}

/** Called by the UI timer when rest runs out while the app is open. */
export function restFinished() {
  if (state.active?.restEndsAt != null) mutate((w) => { w.restEndsAt = null; });
}

export function toggleSet(ex, s) {
  const w = state.active;
  if (!w?.exercises[ex]?.sets[s]) return;
  const done = !w.exercises[ex].sets[s].isDone;
  mutate((x) => {
    x.currentIndex = ex;
    x.exercises[ex].sets[s].isDone = done;
    x.exercises[ex].sets[s].completedAt = done ? Date.now() : null;
    if (!done) {
      x.exercises[ex].status = 'pending';
      if (x.effortPendingIndex === ex) x.effortPendingIndex = null;
    }
  });
  if (done) afterSetCompleted(ex);
  else if (isResting(state.active)) skipRest();
}

function afterSetCompleted(ex) {
  const e = state.active.exercises[ex];
  if (nextSetIndex(e) >= 0) return startRest(e.restBetweenSets, false);
  mutate((w) => { w.effortPendingIndex = ex; });
  if (nextPendingIndex(state.active, ex) != null) startRest(e.restAfterExercise, true);
  else skipRest();
}

export function updateSet(ex, s, patch) {
  mutate((w) => {
    const set = w.exercises[ex]?.sets[s];
    if (!set) return;
    if (patch.reps != null) set.reps = Math.max(0, patch.reps);
    if (patch.weight != null) set.weight = Math.max(0, patch.weight);
    if (patch.kind) set.kind = patch.kind;
  });
}

export function addSet(ex, kind) {
  mutate((w) => {
    const e = w.exercises[ex];
    if (!e) return;
    const sets = e.sets;
    const tpl = [...sets].reverse().find((x) => x.kind === kind) || [...sets].reverse().find((x) => x.kind === 'normal') || sets[sets.length - 1];
    let weight = tpl?.weight ?? 0;
    if (kind === 'drop' && tpl?.kind !== 'drop') weight = roundTo(weight * 0.8, increment(e.equipments));
    const reps = tpl?.reps ?? 10;
    const ns = { id: uid(), kind, targetReps: reps, targetWeight: weight, reps, weight, isDone: false, completedAt: null };
    if (kind === 'warmup') {
      const i = sets.findIndex((x) => x.kind !== 'warmup');
      sets.splice(i < 0 ? sets.length : i, 0, ns);
    } else if (kind === 'normal') {
      let last = -1;
      sets.forEach((x, i) => { if (x.kind === 'normal') last = i; });
      sets.splice(last < 0 ? sets.length : last + 1, 0, ns);
    } else sets.push(ns);
    e.status = 'pending';
    if (w.effortPendingIndex === ex) w.effortPendingIndex = null;
  });
}

export function removeSet(ex, s) {
  mutate((w) => { const e = w.exercises[ex]; if (e && e.sets.length > 1) e.sets.splice(s, 1); });
}

/** Applies an overload suggestion to the sets that aren't done yet. */
export function applySuggestion(ex, sug) {
  mutate((w) => {
    const e = w.exercises[ex];
    const applied = applyToSets(sug, e.sets.map((s) => ({ kind: s.kind, reps: s.targetReps, weight: s.targetWeight })), e.equipments);
    e.sets.forEach((s, i) => {
      if (s.isDone) return;
      s.targetReps = s.reps = applied[i].reps;
      s.targetWeight = s.weight = applied[i].weight;
    });
  });
}

export const focusExercise = (ex) => mutate((w) => { w.currentIndex = ex; });

export function requestFinishExercise(ex) {
  mutate((w) => { w.effortPendingIndex = ex; });
  const w = state.active;
  if (!isResting(w) && nextPendingIndex(w, ex) != null) startRest(w.exercises[ex].restAfterExercise, true);
}

export function submitEffort(ex, effort, injured, note) {
  mutate((w) => {
    const e = w.exercises[ex];
    e.effort = effort;
    e.injured = injured;
    e.injuryNote = injured ? note : '';
    e.status = 'completed';
    e.completedAt = Date.now();
    w.effortPendingIndex = null;
    const n = nextPendingIndex(w, ex);
    if (n != null) w.currentIndex = n;
  });
  const w = state.active;
  if (w.finishAfterRating) {
    const next = unratedIndex(w);
    if (next != null) mutate((x) => { x.effortPendingIndex = next; });
    else finishWorkout();
  }
}

export function cancelEffort() {
  mutate((w) => { w.finishAfterRating = false; w.effortPendingIndex = null; });
}

export function skipExercise(ex) {
  mutate((w) => {
    w.exercises[ex].status = 'skipped';
    if (w.effortPendingIndex === ex) w.effortPendingIndex = null;
    const n = nextPendingIndex(w, ex);
    if (n != null) w.currentIndex = n;
  });
}

export function addExerciseToWorkout(planned) {
  mutate((w) => {
    w.exercises.push(loggedFromPlanned(planned));
    if (w.exercises[w.currentIndex].status !== 'pending') w.currentIndex = w.exercises.length - 1;
  });
}

/** Finish button: ask for any missing effort rating first, then finish. */
export function requestFinish() {
  const w = state.active;
  const i = unratedIndex(w);
  if (i != null) mutate((x) => { x.finishAfterRating = true; x.effortPendingIndex = i; });
  else finishWorkout();
}

export function finishWorkout() {
  const w = state.active;
  if (!w) return;
  push.cancelRest();
  const endedAt = Date.now();
  const durationS = (endedAt - w.startedAt) / 1000;
  const exercises = w.exercises.filter((e) => hasProgress(e) || e.status === 'completed');
  const est = estimateCalories({
    minutes: durationS / 60, weightKg: state.settings.bodyWeightKg, age: state.settings.age, sex: state.settings.sex,
  });
  const record = {
    id: uid(), name: w.name, templateId: w.templateId, quick: !w.templateId, startedAt: w.startedAt, endedAt, duration: durationS,
    exercises, finishedEarly: !w.exercises.every(isFinished),
    calories: est.kcal, caloriesSource: est.source, watchCalories: null, avgHeartRate: null,
  };
  setState((s) => {
    let templates = s.templates;
    if (w.templateId && s.settings.updateTemplateAfterWorkout) {
      templates = templates.map((t) => {
        if (t.id !== w.templateId) return t;
        const items = t.items.map((item) => {
          const log = exercises.find((e) => e.exerciseId === item.exerciseId && hasProgress(e));
          return log ? { ...asPlanned(log), id: item.id, notes: item.notes } : item;
        });
        return { ...t, items, updatedAt: endedAt };
      });
    }
    return { records: [...s.records, record], templates, active: null, lastFinishedId: record.id };
  });
}

export function discardWorkout() {
  push.cancelRest();
  setState({ active: null });
}

export const closeSummary = () => setState({ lastFinishedId: null });

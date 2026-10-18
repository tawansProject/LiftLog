import { hasProgress, topSet, asPlanned, plannedFromExercise } from './models.js';
import { suggest } from './progression.js';
import { uid } from './format.js';

/** Logs of one exercise, newest first, only where something was done. */
export function logsFor(exerciseId, records, before = null) {
  return records
    .filter((r) => before == null || r.startedAt < before)
    .sort((a, b) => b.startedAt - a.startedAt)
    .flatMap((r) => r.exercises.filter((e) => e.exerciseId === exerciseId && hasProgress(e)));
}

export function lastLogWithDate(exerciseId, records) {
  for (const r of [...records].sort((a, b) => b.startedAt - a.startedAt)) {
    const log = r.exercises.find((e) => e.exerciseId === exerciseId && hasProgress(e));
    if (log) return { log, date: r.endedAt };
  }
  return null;
}

export const suggestionFor = (exerciseId, records) => suggest(logsFor(exerciseId, records).slice(0, 5));

/**
 * What to start from when an exercise is added: the last performed record,
 * else the same exercise in another saved session, else defaults.
 */
export function prefill(ex, records, templates, settings) {
  const last = logsFor(ex.exerciseId, records)[0];
  if (last) return { plan: asPlanned(last), note: 'Filled in from your last workout' };
  const fromTemplate = [...templates].sort((a, b) => b.updatedAt - a.updatedAt)
    .map((t) => t.items.find((i) => i.exerciseId === ex.exerciseId)).find(Boolean);
  if (fromTemplate) {
    return {
      plan: { ...structuredClone(fromTemplate), id: uid(), sets: fromTemplate.sets.map((s) => ({ ...s, id: uid() })) },
      note: 'Filled in from another saved session',
    };
  }
  return { plan: plannedFromExercise(ex, settings), note: null };
}

export function bestWeight(exerciseId, records, before) {
  const ws = logsFor(exerciseId, records, before).map((l) => topSet(l)?.weight || 0);
  return ws.length ? Math.max(...ws) : 0;
}

/** Epley estimated one-rep max. */
export function e1rm(weight, reps) {
  if (!weight || !reps) return 0;
  return reps === 1 ? weight : weight * (1 + reps / 30);
}

export function personalRecords(record, all) {
  return record.exercises.flatMap((e) => {
    const top = topSet(e);
    if (!top || top.weight <= 0) return [];
    const prev = bestWeight(e.exerciseId, all, record.startedAt);
    return prev > 0 && top.weight > prev ? [{ name: e.name, weight: top.weight, reps: top.reps, previousBest: prev }] : [];
  });
}

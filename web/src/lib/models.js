import { uid, capitalize } from './format.js';

export const plannedSet = (kind = 'normal', reps = 10, weight = 0) => ({ id: uid(), kind, reps, weight });

export function plannedFromExercise(ex, settings) {
  return {
    id: uid(),
    exerciseId: ex.exerciseId,
    name: capitalize(ex.name),
    gifUrl: ex.gifUrl || null,
    bodyParts: ex.bodyParts || [],
    targetMuscles: ex.targetMuscles || [],
    secondaryMuscles: ex.secondaryMuscles || [],
    equipments: ex.equipments || [],
    sets: [plannedSet(), plannedSet(), plannedSet()],
    restBetweenSets: settings.restBetweenSets,
    restAfterExercise: settings.restAfterExercise,
    notes: '',
  };
}

export function loggedFromPlanned(p) {
  return {
    id: uid(),
    exerciseId: p.exerciseId,
    name: p.name,
    gifUrl: p.gifUrl,
    bodyParts: p.bodyParts,
    targetMuscles: p.targetMuscles,
    secondaryMuscles: p.secondaryMuscles,
    equipments: p.equipments,
    sets: p.sets.map((s) => ({
      id: uid(), kind: s.kind, targetReps: s.reps, targetWeight: s.weight,
      reps: s.reps, weight: s.weight, isDone: false, completedAt: null,
    })),
    restBetweenSets: p.restBetweenSets,
    restAfterExercise: p.restAfterExercise,
    effort: null,
    injured: false,
    injuryNote: '',
    status: 'pending',
    completedAt: null,
  };
}

// Helpers over a logged exercise (same meaning as the native app).
export const doneSets = (e) => e.sets.filter((s) => s.isDone);
export const workingSets = (e) => e.sets.filter((s) => s.kind === 'normal');
export const doneWorkingSets = (e) => workingSets(e).filter((s) => s.isDone);
export const setVolume = (s) => (s.isDone ? s.reps * s.weight : 0);
export const exVolume = (e) => e.sets.filter((s) => s.kind !== 'warmup').reduce((t, s) => t + setVolume(s), 0);
export const hasProgress = (e) => e.sets.some((s) => s.isDone);
export const allSetsDone = (e) => e.sets.length > 0 && e.sets.every((s) => s.isDone);
export const isFinished = (e) => e.status !== 'pending' || allSetsDone(e);
export const recordVolume = (r) => r.exercises.reduce((t, e) => t + exVolume(e), 0);

export function topSet(e) {
  return doneWorkingSets(e).reduce((best, s) => {
    if (!best) return s;
    if (s.weight === best.weight) return s.reps > best.reps ? s : best;
    return s.weight > best.weight ? s : best;
  }, null);
}

/** What was actually done, turned back into a plan for next time. */
export function asPlanned(e) {
  return {
    id: uid(),
    exerciseId: e.exerciseId,
    name: e.name,
    gifUrl: e.gifUrl,
    bodyParts: e.bodyParts,
    targetMuscles: e.targetMuscles,
    secondaryMuscles: e.secondaryMuscles,
    equipments: e.equipments,
    restBetweenSets: e.restBetweenSets,
    restAfterExercise: e.restAfterExercise,
    notes: '',
    sets: e.sets.map((s) => ({
      id: uid(), kind: s.kind,
      reps: s.isDone ? s.reps : s.targetReps,
      weight: s.isDone ? s.weight : s.targetWeight,
    })),
  };
}

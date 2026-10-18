import { weight as fmtW } from './format.js';
import { doneWorkingSets, workingSets, topSet } from './models.js';

export const REP_CEILING = 15;
export const REP_FLOOR = 6;

export const ACTIONS = {
  increaseWeight: { label: 'Add weight', icon: '▲', tone: 'up' },
  increaseReps: { label: 'Add reps', icon: '▲', tone: 'up' },
  hold: { label: 'Repeat', icon: '=', tone: 'hold' },
  decrease: { label: 'Lighten', icon: '▼', tone: 'down' },
  deload: { label: 'Deload', icon: '▼', tone: 'down' },
  recover: { label: 'Recover', icon: '+', tone: 'down' },
};

/** Smallest sensible step in kg: 2 for dumbbells/kettlebells, 2.5 otherwise. */
export function increment(equipments = []) {
  return equipments.some((e) => /dumbbell|kettlebell/i.test(e)) ? 2 : 2.5;
}

export function roundTo(w, inc) {
  return inc > 0 ? Math.round(w / inc) * inc : w;
}

const hitAllTargets = (log) => workingSets(log).every((s) => s.isDone && s.reps >= s.targetReps);

/**
 * Progressive overload rules, driven by effort (1-10) and the injured flag.
 * `history` is the most recent logs of one exercise, newest first.
 *
 * - Injured last time: ~20% lighter (bodyweight: ~30% fewer reps); injured in
 *   2 of the last 3 also suggests swapping or resting the exercise.
 * - All working sets hit target: effort <=5 two weight steps, 6-7 one step,
 *   8 one more rep per set (weight once at 15 reps), 9-10 repeat. First clean
 *   session after an injury: at most one small step.
 * - Missed reps: >=85% of target repeat, otherwise ~10% lighter.
 * - Stalled (same top weight 3 sessions, never hitting target): 10% deload.
 */
export function suggest(history) {
  const logs = history.filter((l) => doneWorkingSets(l).length > 0);
  const last = logs[0];
  const top = last && topSet(last);
  if (!top) return null;

  const step = increment(last.equipments);
  const isBW = top.weight === 0;
  const topW = top.weight;
  const repsAtTop = Math.min(...doneWorkingSets(last).filter((s) => s.weight === topW).map((s) => s.reps));
  const targetReps = Math.max(...workingSets(last).map((s) => s.targetReps), repsAtTop);
  const effort = last.effort ?? 7;
  const working = workingSets(last);
  const hitAll = hitAllTargets(last);
  const targetTotal = working.reduce((t, s) => t + s.targetReps, 0);
  const doneTotal = working.filter((s) => s.isDone).reduce((t, s) => t + s.reps, 0);
  const completion = targetTotal > 0 ? doneTotal / targetTotal : 1;

  const make = (action, w, reps, reason) => {
    if (last.effort == null && action !== 'recover') reason += ' (No effort was recorded last time, so effort 7 was assumed.)';
    return { action, previousWeight: topW, previousReps: repsAtTop, weight: Math.max(0, w), reps: Math.max(1, reps), reason };
  };

  const recentInjuries = logs.slice(0, 3).filter((l) => l.injured).length;
  if (last.injured) {
    let reason = 'You flagged an injury last time. Go about 20% lighter and keep every rep pain-free.';
    if (recentInjuries >= 2) reason += ` It's been flagged in ${recentInjuries} of your last 3 sessions, so consider swapping this exercise or resting it.`;
    if (last.injuryNote) reason += ` Note: ${last.injuryNote}`;
    if (isBW) return make('recover', 0, Math.round(repsAtTop * 0.7), reason);
    return make('recover', roundTo(topW * 0.8, step), repsAtTop, reason);
  }

  const returning = logs.length > 1 && logs[1].injured;

  if (logs.length >= 3 && !isBW) {
    const three = logs.slice(0, 3);
    const same = three.every((l) => topSet(l)?.weight === topW);
    const noneHit = three.every((l) => !hitAllTargets(l));
    if (same && noneHit) {
      return make('deload', roundTo(topW * 0.9, step), targetReps, `Stuck at ${fmtW(topW)} for 3 sessions. Deload 10% and build back up.`);
    }
  }

  if (hitAll) {
    if (returning) {
      if (isBW) return make('increaseReps', 0, repsAtTop + 1, 'First clean session after an injury. Add just one rep.');
      return make('increaseWeight', topW + step, repsAtTop, 'First clean session after an injury. One small step up only.');
    }
    if (effort <= 5) {
      if (isBW) return make('increaseReps', 0, repsAtTop + 2, `Felt easy (effort ${effort}). Add 2 reps per set.`);
      return make('increaseWeight', topW + step * 2, repsAtTop, `Felt easy (effort ${effort}). Jump up ${fmtW(step * 2)}.`);
    }
    if (effort <= 7) {
      if (isBW) return make('increaseReps', 0, repsAtTop + 1, `Solid work (effort ${effort}). Add a rep per set.`);
      return make('increaseWeight', topW + step, repsAtTop, `Solid work (effort ${effort}). Add ${fmtW(step)}.`);
    }
    if (effort === 8) {
      if (isBW || repsAtTop < REP_CEILING) {
        return make('increaseReps', topW, repsAtTop + 1, 'Hard but complete (effort 8). Add one rep per set before adding weight.');
      }
      const r = Math.max(REP_FLOOR, repsAtTop - 4);
      return make('increaseWeight', topW + step, r, `You're at ${repsAtTop} reps. Add ${fmtW(step)} and drop to ${r} reps.`);
    }
    return make('hold', topW, repsAtTop, `Done, but near your limit (effort ${effort}). Repeat it until it feels easier.`);
  }

  if (completion >= 0.85 && effort < 10) {
    return make('hold', topW, targetReps, `Almost there (${Math.round(completion * 100)}% of target reps). Repeat the same target.`);
  }
  if (isBW) return make('decrease', 0, Math.max(1, repsAtTop), `Missed reps. Aim for ${Math.max(1, repsAtTop)} clean reps per set.`);
  return make('decrease', roundTo(topW * 0.9, step), targetReps,
    `Missed a good chunk of reps (${Math.round(completion * 100)}%). Drop about 10% and hit every rep.`);
}

export const isChange = (s) => s.weight !== s.previousWeight || s.reps !== s.previousReps;

/** Applies a suggestion to a list of {kind, reps, weight} sets. Warm-up and drop sets keep their ratio. */
export function applyToSets(sug, sets, equipments) {
  const step = increment(equipments);
  const normals = sets.filter((s) => s.kind === 'normal').map((s) => s.weight);
  const oldTop = normals.length ? Math.max(...normals) : sug.previousWeight;
  const ratio = oldTop > 0 ? sug.weight / oldTop : 1;
  return sets.map((s) => {
    if (s.kind === 'normal') return { ...s, weight: sug.weight, reps: sug.reps };
    return s.weight > 0 ? { ...s, weight: roundTo(s.weight * ratio, step) } : s;
  });
}

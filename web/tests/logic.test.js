import { test } from 'node:test';
import assert from 'node:assert/strict';
import { suggest } from '../src/lib/progression.js';
import { currentDayStreak, longestDayStreak, weekStreak, startOfDay, addDays, periodRange } from '../src/lib/stats.js';
import { loadsPlanned } from '../src/lib/muscles.js';
import { estimateCalories } from '../src/lib/calories.js';

const log = (sets, extra = {}) => ({
  exerciseId: 'x', name: 'Bench', equipments: ['dumbbell'], effort: 7, injured: false, injuryNote: '',
  sets: sets.map(([w, r, t = r, done = true, kind = 'normal']) => ({ kind, weight: w, reps: r, targetReps: t, isDone: done })),
  ...extra,
});

test('easy effort jumps two dumbbell steps', () => {
  const s = suggest([log([[30, 12], [30, 12]], { effort: 5 })]);
  assert.equal(s.action, 'increaseWeight');
  assert.equal(s.weight, 34);
});

test('effort 8 adds a rep', () => {
  const s = suggest([log([[30, 10], [30, 10]], { effort: 8 })]);
  assert.equal(s.action, 'increaseReps');
  assert.equal(s.reps, 11);
});

test('injury drops about 20%', () => {
  const s = suggest([log([[30, 10]], { injured: true })]);
  assert.equal(s.action, 'recover');
  assert.equal(s.weight, 24);
});

test('missed reps under 85% lightens', () => {
  const s = suggest([log([[30, 6, 12], [30, 6, 12]])]);
  assert.equal(s.action, 'decrease');
});

test('stall deloads', () => {
  const l = log([[40, 8, 10], [40, 9, 10]], { equipments: ['barbell'] });
  const s = suggest([l, l, l]);
  assert.equal(s.action, 'deload');
  assert.equal(s.weight, 35);
});

test('streaks', () => {
  const today = startOfDay(Date.now());
  const days = new Set([today, addDays(today, -1), addDays(today, -2), addDays(today, -5)]);
  assert.equal(currentDayStreak(days), 3);
  assert.equal(longestDayStreak(days), 3);
  const thisWeek = periodRange('week', Date.now()).start;
  const recs = [0, 1, 2].map((i) => ({ startedAt: thisWeek + i * 3600e3 })).concat([0, 1, 2].map((i) => ({ startedAt: addDays(thisWeek, -7) + i * 3600e3 })));
  assert.equal(weekStreak(recs, 3), 2);
});

test('muscle loads count secondary as half', () => {
  const l = loadsPlanned([{ targetMuscles: ['pectorals'], secondaryMuscles: ['triceps'], sets: [{ kind: 'normal' }, { kind: 'normal' }, { kind: 'warmup' }] }]);
  assert.equal(l[0].muscle, 'pectorals'); assert.equal(l[0].score, 2); assert.equal(l[1].score, 1);
});

test('calories prefer watch, then heart rate, then MET', () => {
  assert.equal(estimateCalories({ minutes: 60, weightKg: 70, age: 30, sex: 'male', watchCalories: 321 }).source, 'watch');
  assert.equal(estimateCalories({ minutes: 60, weightKg: 70, age: 30, sex: 'male', avgHeartRate: 120 }).source, 'heartRate');
  assert.equal(Math.round(estimateCalories({ minutes: 60, weightKg: 70, age: 30, sex: 'male' }).kcal), 368);
});

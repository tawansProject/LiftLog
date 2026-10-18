import { doneSets, exVolume, hasProgress, recordVolume } from './models.js';
import { loadsLogged } from './muscles.js';
import { personalRecords } from './history.js';

const DAY = 86400000;

export const startOfDay = (ms) => { const d = new Date(ms); d.setHours(0, 0, 0, 0); return d.getTime(); };
export const addDays = (ms, n) => { const d = new Date(ms); d.setDate(d.getDate() + n); return d.getTime(); };

/** Week runs Monday to Sunday. */
export function periodRange(period, date) {
  const d = new Date(startOfDay(date));
  if (period === 'week') {
    const offset = (d.getDay() + 6) % 7;
    d.setDate(d.getDate() - offset);
    const start = d.getTime();
    return { start, end: addDays(start, 7) };
  }
  d.setDate(1);
  const start = d.getTime();
  const e = new Date(start); e.setMonth(e.getMonth() + 1);
  return { start, end: e.getTime() };
}

export function shiftPeriod(period, date, n) {
  const d = new Date(date);
  if (period === 'week') d.setDate(d.getDate() + 7 * n); else { d.setDate(1); d.setMonth(d.getMonth() + n); }
  return d.getTime();
}

export function periodStats(period, date, records) {
  const range = periodRange(period, date);
  const inRange = records.filter((r) => r.startedAt >= range.start && r.startedAt < range.end);
  const logs = inRange.flatMap((r) => r.exercises);
  const efforts = logs.map((l) => l.effort).filter((e) => e != null);
  const daily = [];
  for (let day = range.start; day < range.end; day = addDays(day, 1)) {
    const next = addDays(day, 1);
    daily.push({ day, volume: inRange.filter((r) => r.startedAt >= day && r.startedAt < next).reduce((t, r) => t + recordVolume(r), 0) });
  }
  const setsBy = {};
  for (const l of logs) if (hasProgress(l)) setsBy[l.name] = (setsBy[l.name] || 0) + doneSets(l).length;
  return {
    range,
    workouts: inRange.length,
    duration: inRange.reduce((t, r) => t + r.duration, 0),
    calories: inRange.reduce((t, r) => t + (r.calories || 0), 0),
    activeDays: new Set(inRange.map((r) => startOfDay(r.startedAt))).size,
    sets: logs.reduce((t, l) => t + doneSets(l).length, 0),
    volume: logs.reduce((t, l) => t + exVolume(l), 0),
    injuries: logs.filter((l) => l.injured).length,
    averageEffort: efforts.length ? efforts.reduce((a, b) => a + b, 0) / efforts.length : null,
    muscleLoads: loadsLogged(logs),
    daily,
    topExercises: Object.entries(setsBy).sort((a, b) => b[1] - a[1]).slice(0, 5).map(([name, sets]) => ({ name, sets })),
    prs: inRange.flatMap((r) => personalRecords(r, records)),
  };
}

export const change = (cur, prev) => (prev > 0 ? ((cur - prev) / prev) * 100 : null);

export const workoutDays = (records) => new Set(records.map((r) => startOfDay(r.startedAt)));

/** Consecutive days ending today (or yesterday, so the streak survives until a full day is missed). */
export function currentDayStreak(days, today = Date.now()) {
  let day = startOfDay(today);
  if (!days.has(day)) {
    day = addDays(day, -1);
    if (!days.has(day)) return 0;
  }
  let n = 0;
  while (days.has(day)) { n++; day = addDays(day, -1); }
  return n;
}

export function longestDayStreak(days) {
  let best = 0, run = 0, prev = null;
  for (const d of [...days].sort((a, b) => a - b)) {
    run = prev != null && startOfDay(addDays(prev, 1)) === d ? run + 1 : 1;
    best = Math.max(best, run);
    prev = d;
  }
  return best;
}

/** Consecutive Mon-Sun weeks reaching the goal; the current week only counts once reached. */
export function weekStreak(records, goal, today = Date.now()) {
  const counts = {};
  for (const r of records) { const s = periodRange('week', r.startedAt).start; counts[s] = (counts[s] || 0) + 1; }
  let week = periodRange('week', today).start;
  let n = (counts[week] || 0) >= goal ? 1 : 0;
  for (;;) {
    week = periodRange('week', addDays(week, -1)).start;
    if ((counts[week] || 0) < goal) break;
    n++;
  }
  return n;
}

export { DAY };

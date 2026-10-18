import { useState } from 'preact/hooks';
import { useStore } from '../lib/store.js';
import { Segmented, MuscleOverview } from '../components.jsx';
import { BarChart } from '../charts.jsx';
import { periodStats, shiftPeriod, change, workoutDays, currentDayStreak, longestDayStreak, weekStreak, startOfDay, addDays } from '../lib/stats.js';
import { duration, shortDuration, volume, weight as fmtW, num } from '../lib/format.js';

export function ProgressTab() {
  const s = useStore();
  const days = workoutDays(s.records);
  const goal = s.settings.weeklyGoal;
  return (
    <div class="screen">
      <h1>Progress</h1>
      <div class="stat-grid" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
        <div class="stat"><div class="v">🔥 {currentDayStreak(days)}</div><div class="l">Day streak</div></div>
        <div class="stat"><div class="v">{weekStreak(s.records, goal)}</div><div class="l">Weeks at {goal}+/wk</div></div>
        <div class="stat"><div class="v">{longestDayStreak(days)}</div><div class="l">Best streak</div></div>
      </div>
      <StreakCalendar days={days} />
      <PeriodSummary records={s.records} />
    </div>
  );
}

function StreakCalendar({ days }) {
  const [month, setMonth] = useState(() => { const d = new Date(); d.setDate(1); d.setHours(0, 0, 0, 0); return d.getTime(); });
  const first = new Date(month);
  const lead = (first.getDay() + 6) % 7;
  const start = addDays(month, -lead);
  const today = startOfDay(Date.now());
  const cells = Array.from({ length: 42 }, (_, i) => addDays(start, i));
  const inMonth = (d) => new Date(d).getMonth() === first.getMonth();
  const count = cells.filter((d) => inMonth(d) && days.has(d)).length;
  const shift = (n) => { const d = new Date(month); d.setMonth(d.getMonth() + n); setMonth(d.getTime()); };
  return (
    <div class="card mt16">
      <div class="row between mb8">
        <button class="link" onClick={() => shift(-1)}>‹</button>
        <div class="col center"><span class="bold">{first.toLocaleDateString(undefined, { month: 'long', year: 'numeric' })}</span><span class="small muted">{count} workout day{count === 1 ? '' : 's'}</span></div>
        <button class="link" onClick={() => shift(1)}>›</button>
      </div>
      <div class="cal">
        {['M', 'T', 'W', 'T', 'F', 'S', 'S'].map((h, i) => <div class="h" key={i}>{h}</div>)}
        {cells.map((d) => <div key={d} class={`d ${days.has(d) ? 'on' : ''} ${d === today ? 'today' : ''} ${inMonth(d) ? '' : 'other'}`}>{new Date(d).getDate()}</div>)}
      </div>
    </div>
  );
}

function Delta({ cur, prev, invert }) {
  const c = change(cur, prev);
  if (c == null) return <div class="d faint">—</div>;
  const good = invert ? c < 0 : c >= 0;
  return <div class={`d ${good ? 'up' : 'down'}`}>{c >= 0 ? '▲' : '▼'} {Math.abs(Math.round(c))}% vs last</div>;
}

function PeriodSummary({ records }) {
  const [period, setPeriod] = useState('week');
  const [date, setDate] = useState(Date.now());
  const st = periodStats(period, date, records);
  const prev = periodStats(period, shiftPeriod(period, date, -1), records);
  const isCurrent = st.range.end > Date.now();
  const title = period === 'week'
    ? `${new Date(st.range.start).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })} – ${new Date(addDays(st.range.end, -1)).toLocaleDateString(undefined, { day: 'numeric', month: 'short' })}`
    : new Date(st.range.start).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
  const bars = st.daily.map((d, i) => ({
    value: d.volume,
    label: period === 'week' ? ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i] : (i + 1) % 5 === 0 || i === 0 ? String(i + 1) : '',
  }));
  return (
    <>
      <h2>{period === 'week' ? 'Weekly' : 'Monthly'} summary</h2>
      <Segmented options={[['week', 'Week'], ['month', 'Month']]} value={period} onChange={(p) => { setPeriod(p); setDate(Date.now()); }} />
      <div class="row between mt8 mb8">
        <button class="link" onClick={() => setDate(shiftPeriod(period, date, -1))}>‹ Prev</button>
        <span class="bold">{title}</span>
        <button class="link" disabled={isCurrent} style={isCurrent ? { opacity: 0.3 } : null} onClick={() => setDate(shiftPeriod(period, date, 1))}>Next ›</button>
      </div>
      <div class="stat-grid">
        <div class="stat"><div class="v">{st.workouts}</div><div class="l">Workouts · {st.activeDays} days</div><Delta cur={st.workouts} prev={prev.workouts} /></div>
        <div class="stat"><div class="v">{shortDuration(st.duration)}</div><div class="l">Time training</div><Delta cur={st.duration} prev={prev.duration} /></div>
        <div class="stat"><div class="v">{volume(st.volume)}</div><div class="l">Volume lifted</div><Delta cur={st.volume} prev={prev.volume} /></div>
        <div class="stat"><div class="v">{st.sets}</div><div class="l">Sets</div><Delta cur={st.sets} prev={prev.sets} /></div>
        <div class="stat"><div class="v">{Math.round(st.calories)}</div><div class="l">kcal</div><Delta cur={st.calories} prev={prev.calories} /></div>
        <div class="stat"><div class="v">{st.averageEffort ? num(Math.round(st.averageEffort * 10) / 10) : '—'}</div><div class="l">Avg effort{st.injuries ? ` · ⚠︎ ${st.injuries} injur${st.injuries === 1 ? 'y' : 'ies'}` : ''}</div></div>
      </div>
      <div class="card mt16"><div class="small muted mb8">Volume per day</div><BarChart bars={bars} /></div>
      {st.prs.length > 0 && (
        <div class="card"><div class="bold mb8">🏆 Personal records</div>
          {st.prs.map((p, i) => <div key={i} class="row between small" style={{ padding: '3px 0' }}><span>{p.name}</span><span>{fmtW(p.weight)} × {p.reps}</span></div>)}
        </div>
      )}
      {st.topExercises.length > 0 && (
        <div class="card"><div class="bold mb8">Most trained</div>
          {st.topExercises.map((t) => <div key={t.name} class="row between small" style={{ padding: '3px 0' }}><span class="ellipsis">{t.name}</span><span class="muted">{t.sets} sets</span></div>)}
        </div>
      )}
      <div class="card"><div class="bold mb8">Muscles trained</div><MuscleOverview loads={st.muscleLoads} /></div>
    </>
  );
}

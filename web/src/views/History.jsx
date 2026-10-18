import { useState } from 'preact/hooks';
import { useStore, deleteRecord } from '../lib/store.js';
import { push, toast } from '../nav.js';
import { Segmented, SwipeRow } from '../components.jsx';
import { LineChart } from '../charts.jsx';
import { duration, volume, dateLabel, weight as fmtW } from '../lib/format.js';
import { recordVolume, topSet, doneSets } from '../lib/models.js';
import { logsFor, e1rm } from '../lib/history.js';

export function HistoryTab() {
  const [view, setView] = useState('dashboard');
  return (
    <div class="screen">
      <h1>Sessions</h1>
      <Segmented options={[['dashboard', 'Dashboard'], ['list', 'List']]} value={view} onChange={setView} />
      <div class="mt16">{view === 'dashboard' ? <Dashboard /> : <RecordList />}</div>
    </div>
  );
}

const RANGES = [['1', '1M'], ['3', '3M'], ['6', '6M'], ['12', '1Y']];
const shortDate = (ms) => new Date(ms).toLocaleDateString(undefined, { day: 'numeric', month: 'short' });

function Dashboard() {
  const s = useStore();
  const [range, setRange] = useState('3');
  const from = (() => { const d = new Date(); d.setMonth(d.getMonth() - Number(range)); return d.getTime(); })();
  const recs = s.records.filter((r) => r.startedAt >= from).sort((a, b) => a.startedAt - b.startedAt);
  if (!s.records.length) return <div class="empty"><div class="icon">📈</div><p>Your graphs appear after your first workout.</p></div>;
  const pts = (f) => recs.map((r) => ({ x: r.startedAt, y: f(r) })).filter((p) => p.y != null);
  const avgEffort = (r) => { const e = r.exercises.map((x) => x.effort).filter((x) => x != null); return e.length ? e.reduce((a, b) => a + b, 0) / e.length : null; };
  return (
    <>
      <Segmented options={RANGES} value={range} onChange={setRange} />
      <p class="small muted mt8">{recs.length} workout{recs.length === 1 ? '' : 's'} in this range</p>
      <ChartCard title="Volume per workout" sub="kg lifted (reps × weight)"><LineChart points={pts(recordVolume)} format={(v) => (v >= 1000 ? `${(v / 1000).toFixed(1)}t` : Math.round(v))} xLabel={shortDate} /></ChartCard>
      <ChartCard title="Workout time" sub="minutes"><LineChart points={pts((r) => r.duration / 60)} color="#4d8dff" xLabel={shortDate} /></ChartCard>
      <ChartCard title="Calories" sub="kcal"><LineChart points={pts((r) => r.calories || 0)} color="#ffa94d" xLabel={shortDate} /></ChartCard>
      <ChartCard title="Average effort" sub="1–10"><LineChart points={pts(avgEffort)} color="#51cf66" format={(v) => v.toFixed(1)} xLabel={shortDate} /></ChartCard>
      <StrengthProgress records={s.records} from={from} />
    </>
  );
}

function ChartCard({ title, sub, children }) {
  return <div class="card"><div class="row between mb8"><span class="bold">{title}</span><span class="small muted">{sub}</span></div>{children}</div>;
}

function StrengthProgress({ records, from }) {
  const exercises = {};
  for (const r of records) for (const e of r.exercises) if (topSet(e)?.weight > 0) exercises[e.exerciseId] = e.name;
  const ids = Object.keys(exercises);
  const [id, setId] = useState(ids[0]);
  const [metric, setMetric] = useState('top');
  if (!ids.length) return null;
  const cur = exercises[id] ? id : ids[0];
  const series = [];
  for (const r of [...records].sort((a, b) => a.startedAt - b.startedAt)) {
    if (r.startedAt < from) continue;
    const log = r.exercises.find((e) => e.exerciseId === cur);
    const top = log && topSet(log);
    if (!top || !top.weight) continue;
    const best1rm = Math.max(...log.sets.filter((x) => x.isDone && x.kind === 'normal').map((x) => e1rm(x.weight, x.reps)));
    series.push({ x: r.startedAt, y: metric === 'top' ? top.weight : Math.round(best1rm * 10) / 10 });
  }
  const best = logsFor(cur, records).map((l) => topSet(l)?.weight || 0);
  return (
    <div class="card">
      <div class="bold mb8">Strength progress</div>
      <select value={cur} onChange={(e) => setId(e.currentTarget.value)} class="mb8">{ids.map((i) => <option key={i} value={i}>{exercises[i]}</option>)}</select>
      <Segmented options={[['top', 'Top weight'], ['e1rm', 'Est. 1RM']]} value={metric} onChange={setMetric} />
      <div class="mt8"><LineChart points={series} color="#b197fc" format={(v) => `${Math.round(v)}`} xLabel={shortDate} /></div>
      <div class="small muted">Best ever: {fmtW(Math.max(0, ...best))}</div>
    </div>
  );
}

function RecordList() {
  const s = useStore();
  const sorted = [...s.records].sort((a, b) => b.startedAt - a.startedAt);
  if (!sorted.length) return <div class="empty"><div class="icon">📋</div><p>No sessions yet. Finished sessions, from a plan or quick, show up here.</p></div>;
  const groups = [];
  for (const r of sorted) {
    const key = new Date(r.startedAt).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
    if (groups[groups.length - 1]?.key !== key) groups.push({ key, items: [] });
    groups[groups.length - 1].items.push(r);
  }
  return [<p key="hint" class="small faint center">Swipe a session left to edit or delete it.</p>, ...groups.map((g) => (
    <div key={g.key}>
      <h2>{g.key}</h2>
      {g.items.map((r) => (
        <SwipeRow key={r.id} actions={[
          { kind: 'edit', label: 'Edit', onClick: () => push({ type: 'record', id: r.id }) },
          { kind: 'delete', label: 'Delete', onClick: () => { if (confirm(`Delete "${r.name}" from ${dateLabel(r.startedAt)}?`)) { deleteRecord(r.id); toast('Session deleted'); } } },
        ]}>
          <button class="card tap" onClick={() => push({ type: 'record', id: r.id })}>
            <div class="row between"><span class="bold ellipsis">{r.name}{r.quick && <span class="badge-quick">⚡ Quick</span>}</span><span class="small muted">{dateLabel(r.startedAt)}</span></div>
            <div class="small muted">{duration(r.duration)} · {volume(recordVolume(r))} · {r.exercises.reduce((t, e) => t + doneSets(e).length, 0)} sets · {Math.round(r.calories || 0)} kcal{r.exercises.some((e) => e.injured) ? ' · ⚠︎' : ''}</div>
          </button>
        </SwipeRow>
      ))}
    </div>
  ))];
}

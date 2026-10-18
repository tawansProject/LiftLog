import { useState } from 'preact/hooks';
import { useStore, closeSummary, deleteRecord, updateRecordExercise, updateRecordCalories, saveRecordAsPlan } from '../lib/store.js';
import { pop, toast } from '../nav.js';
import { Page, TopBar, BottomBar, Thumb, MuscleOverview, Stepper, BodyMap } from '../components.jsx';
import { duration, volume, weight as fmtW, dateLabel, SET_KINDS } from '../lib/format.js';
import { doneSets, exVolume, topSet, recordVolume, hasProgress } from '../lib/models.js';
import { loadsLogged } from '../lib/muscles.js';
import { personalRecords } from '../lib/history.js';
import { SOURCE_LABEL } from '../lib/calories.js';
import { EffortSheet } from './Workout.jsx';

/** Shown right after finishing, and for any past workout from History. */
export function RecordView({ id, justFinished }) {
  const s = useStore();
  const r = s.records.find((x) => x.id === id);
  const [editing, setEditing] = useState(null);
  const [calOpen, setCalOpen] = useState(false);
  if (!r) return null;
  const prs = personalRecords(r, s.records);
  const sets = r.exercises.reduce((t, e) => t + doneSets(e).length, 0);
  const close = justFinished ? closeSummary : () => pop();
  return (
    <Page>
      <TopBar title={justFinished ? 'Workout summary' : dateLabel(r.startedAt)} left={justFinished ? <span /> : undefined}
        right={!justFinished && <button class="link danger" onClick={() => { if (confirm('Delete this workout from your history?')) { deleteRecord(r.id); pop(); } }}>Delete</button>} />
      {justFinished && <div class="center" style={{ fontSize: 44 }}>🎉</div>}
      <h1 class="center" style={{ fontSize: 26, marginTop: 0 }}>{r.name}</h1>
      <p class="center muted small">{new Date(r.startedAt).toLocaleString(undefined, { weekday: 'long', day: 'numeric', month: 'long', hour: '2-digit', minute: '2-digit' })}{r.finishedEarly ? ' · finished early' : ''}</p>
      <div class="stat-grid">
        <div class="stat"><div class="v">{duration(r.duration)}</div><div class="l">Total time</div></div>
        <div class="stat"><div class="v">{volume(recordVolume(r))}</div><div class="l">Volume</div></div>
        <div class="stat"><div class="v">{sets}</div><div class="l">Sets done</div></div>
        <button class="stat" style={{ textAlign: 'left' }} onClick={() => setCalOpen(!calOpen)}>
          <div class="v">{Math.round(r.calories || 0)} <span class="small">kcal</span></div>
          <div class="l">{SOURCE_LABEL[r.caloriesSource] || 'Calories'}{r.avgHeartRate ? ` · ${r.avgHeartRate} bpm avg` : ''} ✎</div>
        </button>
      </div>
      {calOpen && <CaloriesEditor r={r} onDone={() => setCalOpen(false)} />}

      {!r.templateId && r.exercises.some(hasProgress) && (
        <div class="card mt16">
          <div class="bold">⚡ Quick session</div>
          <p class="small muted">Save it as a workout plan to repeat and edit it later, starting from what you lifted today.</p>
          <button class="btn small" onClick={() => {
            const name = prompt('Name for the workout plan', r.name === 'Quick session' ? '' : r.name);
            if (name == null) return;
            if (saveRecordAsPlan(r.id, name.trim() || `Plan ${dateLabel(r.startedAt)}`)) toast('Saved as workout plan');
          }}>Save as workout plan</button>
        </div>
      )}

      {prs.length > 0 && (
        <>
          <h2>🏆 Personal records</h2>
          <div class="card">{prs.map((p) => <div key={p.name} class="row between small" style={{ padding: '4px 0' }}><span class="bold">{p.name}</span><span>{fmtW(p.weight)} × {p.reps} <span class="muted">(was {fmtW(p.previousBest)})</span></span></div>)}</div>
        </>
      )}

      <h2>Exercises</h2>
      {r.exercises.map((e) => {
        const top = topSet(e);
        return (
          <div class="card" key={e.id}>
            <div class="row">
              <Thumb src={e.gifUrl} id={e.exerciseId} name={e.name} />
              <div class="col grow">
                <div class="bold ellipsis">{e.name}</div>
                <div class="small muted">{doneSets(e).length}/{e.sets.length} sets · {volume(exVolume(e))}{top ? ` · top ${fmtW(top.weight)} × ${top.reps}` : ''}</div>
              </div>
              <button class="chip" onClick={() => setEditing(e)}>{e.effort ? `Effort ${e.effort}` : 'Add effort'}{e.injured ? ' ⚠︎' : ''}</button>
            </div>
            <div class="small muted mt8">
              {e.sets.filter((x) => x.isDone).map((x, i) => <span key={x.id}>{i ? ' · ' : ''}{x.kind !== 'normal' ? `${SET_KINDS[x.kind].badge} ` : ''}{x.weight ? `${x.weight}×${x.reps}` : `${x.reps} reps`}</span>)}
            </div>
            {e.injured && e.injuryNote && <div class="small mt8" style={{ color: 'var(--red)' }}>⚠︎ {e.injuryNote}</div>}
          </div>
        );
      })}

      <h2>Muscles worked</h2>
      <div class="card"><BodyMap loads={loadsLogged(r.exercises)} /></div>
      <div class="card"><MuscleOverview loads={loadsLogged(r.exercises)} /></div>

      {justFinished && <BottomBar><button class="btn" onClick={close}>Done</button></BottomBar>}
      {editing && (
        <EffortSheet ex={editing} onCancel={() => setEditing(null)}
          onSave={(effort, injured, note) => { updateRecordExercise(r.id, editing.id, { effort, injured, injuryNote: injured ? note : '', status: 'completed' }); setEditing(null); }} />
      )}
    </Page>
  );
}

function CaloriesEditor({ r, onDone }) {
  const [kcal, setKcal] = useState(r.watchCalories || 0);
  const [hr, setHr] = useState(r.avgHeartRate || 0);
  return (
    <div class="card mt8">
      <div class="bold mb8">From your Apple Watch</div>
      <p class="small muted">If you tracked this session in the Watch's Workout app, copy the numbers from its summary (Fitness app → workout). Leave 0 to use the estimate.</p>
      <div class="row between mb8"><span>Active calories</span><Stepper value={kcal} step={10} onChange={setKcal} unit="kcal" /></div>
      <div class="row between"><span>Avg heart rate</span><Stepper value={hr} step={1} onChange={setHr} unit="bpm" /></div>
      <button class="btn small mt16" onClick={() => { updateRecordCalories(r.id, { watchCalories: kcal || null, avgHeartRate: hr || null }); onDone(); }}>Update calories</button>
    </div>
  );
}

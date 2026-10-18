import { useEffect, useRef, useState } from 'preact/hooks';
import { useStore, setState, cacheExercise, prefillFor, addExerciseToWorkout } from '../lib/store.js';
import { push, pop, popTo, clear, toast } from '../nav.js';
import { TopBar, Page, BottomBar, Thumb, MuscleChips, Stepper, KindBadge, setNumbers } from '../components.jsx';
import { search, BODY_PARTS } from '../lib/exercisedb.js';
import { capitalize, rest, uid, weight as fmtW, SET_KINDS } from '../lib/format.js';
import { suggestionFor } from '../lib/history.js';
import { ACTIONS, applyToSets, isChange } from '../lib/progression.js';
import { plannedSet } from '../lib/models.js';

export function Search({ mode }) {
  const s = useStore();
  const [q, setQ] = useState('');
  const [part, setPart] = useState(null);
  const [results, setResults] = useState([]);
  const [cursor, setCursor] = useState(null);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);
  const reqId = useRef(0);

  const run = async (more = false) => {
    const id = ++reqId.current;
    setLoading(true); setError(null);
    try {
      const page = await search(q, part, more ? cursor : null);
      if (id !== reqId.current) return;
      setResults(more ? [...results, ...page.data] : page.data);
      setCursor(page.nextCursor);
    } catch (e) {
      if (id === reqId.current) setError(e.message || 'Could not reach the Exercise Library.');
    } finally {
      if (id === reqId.current) setLoading(false);
    }
  };

  useEffect(() => { const t = setTimeout(() => run(false), q ? 350 : 0); return () => clearTimeout(t); }, [q, part]);

  const recent = Object.values(s.exerciseCache).slice(-8).reverse();
  const pick = (ex) => {
    cacheExercise(ex);
    const { plan, note } = prefillFor(ex);
    push({ type: 'config', mode, plan, exercise: ex, note });
  };

  return (
    <Page>
      <TopBar title="Add exercise" right={<button class="link" onClick={() => push({ type: 'custom', mode })}>Custom</button>} />
      <input type="search" placeholder="Search exercises (e.g. bench press)" value={q} onInput={(e) => setQ(e.currentTarget.value)} autoFocus />
      <div class="chips-scroll mt8 mb8">
        <button class={`chip ${!part ? 'on' : ''}`} onClick={() => setPart(null)}>All</button>
        {BODY_PARTS.map((b) => <button key={b} class={`chip ${part === b ? 'on' : ''}`} onClick={() => setPart(part === b ? null : b)}>{capitalize(b)}</button>)}
      </div>
      {!q && !part && recent.length > 0 && (
        <>
          <h2>Recently picked</h2>
          <div class="card">{recent.map((ex) => <ResultRow key={ex.exerciseId} ex={ex} onPick={pick} />)}</div>
          <h2>Exercise Library</h2>
        </>
      )}
      {error && <div class="note warn mb8">{error} <button class="link" onClick={() => run(false)}>Retry</button></div>}
      <div class="card">
        {results.map((ex) => <ResultRow key={ex.exerciseId} ex={ex} onPick={pick} />)}
        {!loading && !results.length && !error && <div class="empty small">No exercises found. Try another word, or add a custom exercise.</div>}
        {loading && <div class="empty small">Searching…</div>}
      </div>
      {cursor && !loading && <button class="btn secondary" onClick={() => run(true)}>Load more</button>}
    </Page>
  );
}

function ResultRow({ ex, onPick }) {
  return (
    <button class="list-btn" onClick={() => onPick(ex)}>
      <Thumb src={ex.gifUrl} name={ex.name} />
      <div class="col grow">
        <div class="bold">{capitalize(ex.name)}</div>
        <div class="small muted ellipsis">Targets: {ex.targetMuscles.map(capitalize).join(', ') || '—'}</div>
        <div class="tiny faint ellipsis">{[...ex.bodyParts, ...ex.equipments].map(capitalize).join(' · ')}</div>
      </div>
      <span class="faint">›</span>
    </button>
  );
}

export function CustomExercise({ mode }) {
  const [name, setName] = useState('');
  const [part, setPart] = useState('chest');
  const [target, setTarget] = useState('');
  const [equipment, setEquipment] = useState('');
  const create = () => {
    const ex = {
      exerciseId: `custom-${uid()}`, name: name.trim(), gifUrl: null, bodyParts: [part],
      targetMuscles: target.split(',').map((t) => t.trim().toLowerCase()).filter(Boolean),
      secondaryMuscles: [], equipments: equipment ? [equipment.toLowerCase()] : [], instructions: [],
    };
    cacheExercise(ex);
    const { plan, note } = prefillFor(ex);
    pop();
    push({ type: 'config', mode, plan, exercise: ex, note });
  };
  return (
    <Page>
      <TopBar title="Custom exercise" />
      <label class="small muted">Name</label>
      <input value={name} onInput={(e) => setName(e.currentTarget.value)} placeholder="e.g. Landmine press" />
      <label class="small muted mt16" style={{ display: 'block' }}>Body part</label>
      <select value={part} onChange={(e) => setPart(e.currentTarget.value)}>{BODY_PARTS.map((b) => <option key={b} value={b}>{capitalize(b)}</option>)}</select>
      <label class="small muted mt16" style={{ display: 'block' }}>Target muscles (comma separated)</label>
      <input value={target} onInput={(e) => setTarget(e.currentTarget.value)} placeholder="e.g. pectorals, triceps" />
      <label class="small muted mt16" style={{ display: 'block' }}>Equipment</label>
      <input value={equipment} onInput={(e) => setEquipment(e.currentTarget.value)} placeholder="e.g. dumbbell" />
      <BottomBar><button class="btn" disabled={!name.trim()} onClick={create}>Continue</button></BottomBar>
    </Page>
  );
}

/** Exercise preview + set / rep / rest setup. */
export function ExerciseConfig({ mode, plan: initial, exercise, note }) {
  const s = useStore();
  const [plan, setPlan] = useState(initial);
  const ex = exercise || s.exerciseCache[plan.exerciseId];
  const sug = suggestionFor(plan.exerciseId, s.records);
  const nums = setNumbers(plan.sets);
  const upd = (patch) => setPlan({ ...plan, ...patch });
  const updSet = (i, patch) => upd({ sets: plan.sets.map((x, j) => (j === i ? { ...x, ...patch } : x)) });
  const addSet = (kind) => {
    const last = [...plan.sets].reverse().find((x) => x.kind === 'normal') || plan.sets[plan.sets.length - 1];
    const w = kind === 'drop' ? Math.round((last?.weight || 0) * 0.8 * 2) / 2 : kind === 'warmup' ? Math.round((last?.weight || 0) * 0.5 * 2) / 2 : last?.weight || 0;
    const ns = plannedSet(kind, last?.reps || 10, w);
    const sets = [...plan.sets];
    if (kind === 'warmup') { const i = sets.findIndex((x) => x.kind !== 'warmup'); sets.splice(i < 0 ? sets.length : i, 0, ns); }
    else if (kind === 'normal') { let li = -1; sets.forEach((x, i) => { if (x.kind === 'normal') li = i; }); sets.splice(li + 1 || sets.length, 0, ns); }
    else sets.push(ns);
    upd({ sets });
  };
  const save = () => {
    if (mode === 'workout') {
      addExerciseToWorkout(plan);
      clear();
      toast(`${plan.name} added`);
      return;
    }
    setState((st) => {
      const items = st.draft.items;
      const exists = items.some((x) => x.id === plan.id);
      return { draft: { ...st.draft, items: exists ? items.map((x) => (x.id === plan.id ? plan : x)) : [...items, plan] } };
    });
    if (mode === 'edit') pop(); else popTo('builder');
  };
  return (
    <Page>
      <TopBar title={mode === 'edit' ? 'Edit exercise' : 'Exercise'} />
      <Thumb src={plan.gifUrl} name={plan.name} lg />
      <h1 style={{ fontSize: 24, marginTop: 14 }}>{plan.name}</h1>
      <div class="small muted mb8">Target muscles</div>
      <MuscleChips muscles={plan.targetMuscles} />
      {plan.secondaryMuscles.length > 0 && <><div class="small muted mt8 mb8">Also works</div><MuscleChips muscles={[]} secondary={plan.secondaryMuscles} /></>}
      {ex?.instructions?.length > 0 && (
        <details class="mt8"><summary>How to do it</summary><ol class="instructions">{ex.instructions.map((t, i) => <li key={i}>{t.replace(/^Step:\d+\s*/, '')}</li>)}</ol></details>
      )}
      {note && <div class="note mt16">↺ {note}</div>}
      {sug && (
        <div class={`card mt16 sug ${ACTIONS[sug.action].tone}`}>
          <div class="row between"><div class="bold">{ACTIONS[sug.action].icon} {ACTIONS[sug.action].label}: {fmtW(sug.weight)} × {sug.reps}</div></div>
          <div class="small muted mt8">{sug.reason}</div>
          {isChange(sug) && <button class="btn small mt8" onClick={() => upd({ sets: applyToSets(sug, plan.sets, plan.equipments) })}>Use suggestion</button>}
        </div>
      )}
      <h2>Sets</h2>
      <div class="card">
        <div class="set-row small muted" style={{ paddingTop: 0 }}><span>Set</span><span>Reps</span><span>kg</span><span /></div>
        {plan.sets.map((set, i) => (
          <div class="set-row" key={set.id}>
            <button onClick={() => updSet(i, { kind: set.kind === 'normal' ? 'warmup' : set.kind === 'warmup' ? 'drop' : 'normal' })} title="Tap to change type"><KindBadge kind={set.kind} index={nums[i]} /></button>
            <SmallStepper value={set.reps} onChange={(v) => updSet(i, { reps: v })} step={1} min={1} />
            <SmallStepper value={set.weight} onChange={(v) => updSet(i, { weight: v })} step={plan.equipments.some((e) => /dumbbell|kettlebell/.test(e)) ? 2 : 2.5} decimals />
            <button class="link danger" disabled={plan.sets.length < 2} onClick={() => upd({ sets: plan.sets.filter((_, j) => j !== i) })} aria-label="Remove set">✕</button>
          </div>
        ))}
        <div class="small faint mt8">Tap the number to switch between normal, warm-up (W) and drop set (D). 0 kg = bodyweight.</div>
        <div class="gap8 mt8">
          <button class="btn secondary small" onClick={() => addSet('normal')}>＋ Set</button>
          <button class="btn secondary small" onClick={() => addSet('warmup')}>＋ Warm-up</button>
          <button class="btn secondary small" onClick={() => addSet('drop')}>＋ Drop set</button>
        </div>
      </div>
      <h2>Rest timers</h2>
      <div class="card">
        <div class="row between mb8"><span>Between sets</span><Stepper value={plan.restBetweenSets} onChange={(v) => upd({ restBetweenSets: v })} step={15} unit="s" /></div>
        <div class="row between"><span>Before next exercise</span><Stepper value={plan.restAfterExercise} onChange={(v) => upd({ restAfterExercise: v })} step={15} unit="s" /></div>
        <div class="small faint mt8">{rest(plan.restBetweenSets)} between sets, {rest(plan.restAfterExercise)} before the next exercise.</div>
      </div>
      <BottomBar><button class="btn" onClick={save}>{mode === 'edit' ? 'Save changes' : mode === 'workout' ? 'Add to workout' : 'Add to session'}</button></BottomBar>
    </Page>
  );
}

export function SmallStepper(props) {
  return <Stepper {...props} width={44} />;
}

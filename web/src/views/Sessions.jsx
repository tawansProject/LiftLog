import { useStore, setState, getState, saveTemplate, deleteTemplate, duplicateTemplate, startWorkout } from '../lib/store.js';
import { push, pop, clear, toast } from '../nav.js';
import { TopBar, Page, BottomBar, Thumb, MuscleOverview, MuscleChips } from '../components.jsx';
import { loadsPlanned, groupTotals, GROUPS } from '../lib/muscles.js';
import { setSummary, rest, uid, dateLabel } from '../lib/format.js';
import { suggestionFor } from '../lib/history.js';
import { ACTIONS, isChange } from '../lib/progression.js';
import { duration } from '../lib/format.js';

export function SessionsTab() {
  const s = useStore();
  const lastDone = (t) => {
    const r = s.records.filter((x) => x.templateId === t.id).sort((a, b) => b.startedAt - a.startedAt)[0];
    return r ? `Last done ${dateLabel(r.startedAt)}` : 'Not done yet';
  };
  const newSession = () => {
    setState({ draft: { id: uid(), name: '', items: [], isNew: true } });
    push({ type: 'builder' });
  };
  return (
    <div class="screen">
      <h1>Workouts</h1>
      {s.active && (
        <button class="card tap raised" onClick={() => setState({ workoutHidden: false })}>
          <div class="row"><div class="grow"><div class="bold">Workout in progress</div><div class="small muted">{s.active.name} · started {duration((Date.now() - s.active.startedAt) / 1000)} ago</div></div><span class="link">Resume ›</span></div>
        </button>
      )}
      <button class="btn mb8" onClick={newSession}>＋ New session</button>
      <h2>Your sessions</h2>
      {!s.templates.length && (
        <div class="empty"><div class="icon">🏋️</div><p>No sessions yet.</p><p class="small">Create one: search exercises, set your sets, reps and rest, then save it to reuse anytime.</p></div>
      )}
      {[...s.templates].sort((a, b) => b.updatedAt - a.updatedAt).map((t) => {
        const groups = groupTotals(loadsPlanned(t.items)).slice(0, 4);
        return (
          <button class="card tap" key={t.id} onClick={() => push({ type: 'template', id: t.id })}>
            <div class="row between"><h3 class="ellipsis">{t.name || 'Untitled session'}</h3><span class="faint">›</span></div>
            <div class="small muted mb8">{t.items.length} exercise{t.items.length === 1 ? '' : 's'} · {lastDone(t)}</div>
            <div class="gap8">{groups.map((g) => <span class="chip" key={g.group}><span class="dot" style={{ background: GROUPS[g.group].color }} />{GROUPS[g.group].label}</span>)}</div>
          </button>
        );
      })}
    </div>
  );
}

export function TemplateDetail({ id }) {
  const s = useStore();
  const t = s.templates.find((x) => x.id === id);
  if (!t) return null;
  const edit = () => { setState({ draft: structuredClone(t) }); push({ type: 'builder' }); };
  const start = () => {
    if (s.active && !confirm('A workout is already in progress. Discard it and start this one?')) return;
    startWorkout(t.name, t.id, t.items);
    clear();
    setState({ workoutHidden: false });
  };
  return (
    <Page>
      <TopBar title={t.name} right={<button class="link" onClick={edit}>Edit</button>} />
      <h2>Exercises</h2>
      {t.items.map((p, i) => {
        const sug = suggestionFor(p.exerciseId, s.records);
        return (
          <div class="card" key={p.id}>
            <div class="row">
              <Thumb src={p.gifUrl} name={p.name} onClick={() => push({ type: 'gif', src: p.gifUrl, name: p.name })} />
              <div class="col grow">
                <div class="bold">{i + 1}. {p.name}</div>
                <div class="small muted">{setSummary(p)} · rest {rest(p.restBetweenSets)}</div>
                {sug && isChange(sug) && <div class={`small ${ACTIONS[sug.action].tone}`}>{ACTIONS[sug.action].icon} Next: {ACTIONS[sug.action].label.toLowerCase()} ({sug.weight ? `${sug.weight} kg` : 'BW'} × {sug.reps})</div>}
              </div>
            </div>
          </div>
        );
      })}
      <h2>Muscles this session hits</h2>
      <div class="card"><MuscleOverview loads={loadsPlanned(t.items)} /></div>
      <div class="gap8 mt16">
        <button class="btn secondary small" onClick={() => { duplicateTemplate(t.id); toast('Session duplicated'); pop(); }}>Duplicate</button>
        <button class="btn danger small" onClick={() => { if (confirm(`Delete "${t.name}"? Your workout history stays.`)) { deleteTemplate(t.id); pop(); } }}>Delete</button>
      </div>
      <BottomBar><button class="btn" disabled={!t.items.length} onClick={start}>▶ Start workout</button></BottomBar>
    </Page>
  );
}

export function GifPage({ src, name }) {
  return (
    <Page>
      <TopBar title={name} />
      <Thumb src={src} name={name} lg />
    </Page>
  );
}

function moveItem(items, i, d) {
  const j = i + d;
  if (j < 0 || j >= items.length) return items;
  const next = [...items];
  [next[i], next[j]] = [next[j], next[i]];
  return next;
}

export function Builder() {
  const s = useStore();
  const d = s.draft;
  if (!d) return null;
  const setDraft = (patch) => setState((st) => ({ draft: { ...st.draft, ...patch } }));
  const cancel = () => {
    if (d.items.length && !confirm('Discard changes to this session?')) return;
    setState({ draft: null }); pop();
  };
  return (
    <Page>
      <TopBar title={d.isNew ? 'New session' : 'Edit session'} left={<button class="link" onClick={cancel}>Cancel</button>} />
      <input placeholder="Session name, e.g. Session A: Push" value={d.name} onInput={(e) => setDraft({ name: e.currentTarget.value })} />
      <h2>Exercises</h2>
      {!d.items.length && <p class="muted small">Search the Exercise Library and add as many exercises as you like. Each one shows the muscles it targets.</p>}
      {d.items.map((p, i) => (
        <div class="card" key={p.id}>
          <div class="row">
            <Thumb src={p.gifUrl} name={p.name} />
            <button class="col grow" style={{ textAlign: 'left' }} onClick={() => push({ type: 'config', mode: 'edit', plan: p })}>
              <div class="bold ellipsis">{i + 1}. {p.name}</div>
              <div class="small muted">{setSummary(p)}</div>
              <div class="small muted">Rest {rest(p.restBetweenSets)} between sets · {rest(p.restAfterExercise)} after</div>
            </button>
            <div class="col" style={{ gap: 0 }}>
              <button class="link" style={{ padding: '2px 8px' }} onClick={() => setDraft({ items: moveItem(d.items, i, -1) })} aria-label="Move up">▲</button>
              <button class="link" style={{ padding: '2px 8px' }} onClick={() => setDraft({ items: moveItem(d.items, i, 1) })} aria-label="Move down">▼</button>
            </div>
          </div>
          <div class="row between mt8">
            <MuscleChips muscles={p.targetMuscles} />
            <button class="link danger small" onClick={() => setDraft({ items: d.items.filter((x) => x.id !== p.id) })}>Remove</button>
          </div>
        </div>
      ))}
      <button class="btn secondary" onClick={() => push({ type: 'search', mode: 'add' })}>＋ Add exercise</button>
      <BottomBar>
        <button class="btn" disabled={!d.items.length} onClick={() => push({ type: 'review' })}>Review ›</button>
      </BottomBar>
    </Page>
  );
}

export function Review() {
  const s = useStore();
  const d = s.draft;
  if (!d) return null;
  const name = d.name.trim() || `Session ${String.fromCharCode(65 + (s.templates.length % 26))}`;
  const save = (andStart) => {
    const t = { id: d.id, name, items: d.items, createdAt: d.createdAt };
    saveTemplate(t);
    setState({ draft: null });
    clear();
    if (andStart) {
      if (getState().active && !confirm('A workout is already in progress. Discard it and start this one?')) return;
      startWorkout(name, d.id, d.items);
      setState({ workoutHidden: false });
    } else {
      push({ type: 'template', id: d.id });
    }
    toast('Session saved');
  };
  const totalSets = d.items.reduce((t, p) => t + p.sets.length, 0);
  return (
    <Page>
      <TopBar title="Confirm session" />
      <h1 style={{ fontSize: 26 }}>{name}</h1>
      <p class="muted">{d.items.length} exercises · {totalSets} sets</p>
      <h2>Muscles you'll work</h2>
      <div class="card"><MuscleOverview loads={loadsPlanned(d.items)} /></div>
      <h2>Order</h2>
      <div class="card">
        {d.items.map((p, i) => (
          <div class="list-btn" key={p.id}>
            <Thumb src={p.gifUrl} name={p.name} />
            <div class="col grow"><div class="bold ellipsis">{i + 1}. {p.name}</div><div class="small muted">{setSummary(p)}</div></div>
          </div>
        ))}
      </div>
      <BottomBar>
        <button class="btn secondary" onClick={() => save(false)}>Save</button>
        <button class="btn" onClick={() => save(true)}>Save & start</button>
      </BottomBar>
    </Page>
  );
}

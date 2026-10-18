import { useEffect, useRef, useState } from 'preact/hooks';
import * as W from '../lib/store.js';
import { useStore, setState } from '../lib/store.js';
import { push } from '../nav.js';
import { Thumb, MuscleChips, KindBadge, setNumbers, useNow, Ring, Sheet, Stepper } from '../components.jsx';
import { duration, rest as fmtRest, weight as fmtW } from '../lib/format.js';
import { suggestionFor } from '../lib/history.js';
import { ACTIONS, isChange } from '../lib/progression.js';
import { isFinished, hasProgress } from '../lib/models.js';
import { beep } from '../lib/sound.js';

export function LiveWorkout() {
  const s = useStore();
  const w = s.active;
  const now = useNow(250);
  const [menu, setMenu] = useState(false);
  useWakeLock(s.settings.keepAwake);

  // Rest ran out while the app is open: sound + clear.
  const resting = w.restEndsAt != null && w.restEndsAt > now;
  const restWasActive = useRef(false);
  useEffect(() => {
    if (w.restEndsAt != null && w.restEndsAt <= now) {
      if (restWasActive.current && s.settings.sound) beep();
      W.restFinished();
    }
    restWasActive.current = resting;
  }, [now, w.restEndsAt]);

  const ex = w.exercises[w.currentIndex];
  const finished = w.exercises.filter(isFinished).length;
  const pendingRating = w.effortPendingIndex;

  return (
    <div class="overlay">
      <div class="screen">
        <div class="topbar">
          <div class="side"><button class="link white" onClick={() => setState({ workoutHidden: true })}>⌄ Hide</button></div>
          <div class="title">{w.name}</div>
          <div class="side right"><button class="link" onClick={() => setMenu(true)}>•••</button></div>
        </div>

        <div class="center mb8">
          <div class="small muted">Total time</div>
          <div class="timer-big">{duration((now - w.startedAt) / 1000)}</div>
          <div class="small muted">{finished} of {w.exercises.length} exercises done</div>
        </div>

        {resting && (
          <div class="rest">
            <Ring progress={(w.restEndsAt - now) / 1000 / Math.max(1, w.restTotal)} />
            <div class="grow">
              <div class="small bold">{w.restBetweenExercises ? 'Rest before next exercise' : 'Rest between sets'}</div>
              <div class="timer-big" style={{ fontSize: 34 }}>{duration(Math.ceil((w.restEndsAt - now) / 1000))}</div>
              <div class="tiny ellipsis">{W.nextUpDescription(w)}</div>
            </div>
            <div class="col" style={{ gap: 6 }}>
              <button class="btn small" onClick={() => W.addRest(15)}>+15s</button>
              <button class="btn small" onClick={() => W.skipRest()}>Skip</button>
            </div>
          </div>
        )}

        <div class="strip">
          {w.exercises.map((e, i) => (
            <button key={e.id} class={`${i === w.currentIndex ? 'cur' : ''} ${isFinished(e) ? 'done' : ''}`} onClick={() => W.focusExercise(i)}>
              <Thumb src={e.gifUrl} name={e.name} />
              <div class="ellipsis">{e.status === 'completed' ? '✓ ' : e.status === 'skipped' ? '⤼ ' : ''}{i + 1}. {e.name}</div>
            </button>
          ))}
          <button onClick={() => push({ type: 'search', mode: 'workout' })}><div class="thumb ph">＋</div><div>Add</div></button>
        </div>

        {ex && <ExerciseCard ex={ex} index={w.currentIndex} records={s.records} />}
      </div>

      <div class="bottom-bar"><div>
        {ex && ex.status === 'pending'
          ? <button class="btn secondary" onClick={() => W.requestFinishExercise(w.currentIndex)}>Done with exercise</button>
          : null}
        <button class="btn" onClick={() => {
          if (!w.exercises.some(hasProgress)) {
            if (confirm('No sets are ticked yet, so there is nothing to save. Discard this workout?')) W.discardWorkout();
            return;
          }
          W.requestFinish();
        }}>Finish workout</button>
      </div></div>

      {pendingRating != null && w.exercises[pendingRating] && <EffortSheet index={pendingRating} ex={w.exercises[pendingRating]} />}
      {menu && (
        <Sheet onClose={() => setMenu(false)}>
          <h3>Workout</h3>
          <button class="btn secondary mt8" onClick={() => { setMenu(false); push({ type: 'search', mode: 'workout' }); }}>＋ Add exercise</button>
          {ex?.status === 'pending' && <button class="btn secondary mt8" onClick={() => { W.skipExercise(w.currentIndex); setMenu(false); }}>Skip {ex.name}</button>}
          <button class="btn danger mt8" onClick={() => { if (confirm('Discard this workout? Nothing will be saved.')) { setMenu(false); W.discardWorkout(); } }}>Discard workout</button>
          <button class="btn secondary mt8" onClick={() => setMenu(false)}>Close</button>
        </Sheet>
      )}
    </div>
  );
}

function ExerciseCard({ ex, index, records }) {
  const nums = setNumbers(ex.sets);
  const sug = suggestionFor(ex.exerciseId, records);
  const nextSet = ex.sets.findIndex((s) => !s.isDone);
  const step = ex.equipments.some((e) => /dumbbell|kettlebell/.test(e)) ? 2 : 2.5;
  const untouched = !hasProgress(ex);
  return (
    <div>
      <div class="card">
        <div class="row">
          <Thumb src={ex.gifUrl} name={ex.name} onClick={() => ex.gifUrl && push({ type: 'gif', src: ex.gifUrl, name: ex.name })} />
          <div class="col grow">
            <h3 style={{ margin: 0 }}>{index + 1}. {ex.name}</h3>
            <MuscleChips muscles={ex.targetMuscles} />
          </div>
        </div>
        {ex.status === 'completed' && <div class="small muted mt8">Effort {ex.effort ?? '—'}/10{ex.injured ? ' · ⚠︎ injured' : ''}</div>}
        {ex.status === 'skipped' && <div class="small muted mt8">Skipped</div>}
      </div>

      {sug && untouched && isChange(sug) && ex.status === 'pending' && (
        <div class={`card sug ${ACTIONS[sug.action].tone}`}>
          <div class="bold">{ACTIONS[sug.action].icon} {ACTIONS[sug.action].label}: {fmtW(sug.weight)} × {sug.reps}</div>
          <div class="small muted mt8">{sug.reason}</div>
          <button class="btn small mt8" onClick={() => W.applySuggestion(index, sug)}>Apply to my sets</button>
        </div>
      )}

      <div class="card">
        <div class="set-row small muted" style={{ paddingTop: 0 }}><span>Set</span><span>Reps</span><span>kg</span><span>Done</span></div>
        {ex.sets.map((set, i) => (
          <div class={`set-row ${set.isDone ? 'done' : ''}`} key={set.id} style={i === nextSet ? { background: 'rgba(255,255,255,0.04)', borderRadius: 10 } : null}>
            <button onClick={() => !set.isDone && W.updateSet(index, i, { kind: set.kind === 'normal' ? 'warmup' : set.kind === 'warmup' ? 'drop' : 'normal' })}><KindBadge kind={set.kind} index={nums[i]} /></button>
            <Stepper width={40} value={set.reps} onChange={(v) => W.updateSet(index, i, { reps: v })} />
            <Stepper width={44} value={set.weight} decimals step={step} onChange={(v) => W.updateSet(index, i, { weight: v })} />
            <button class={`check ${set.isDone ? 'on' : ''}`} onClick={() => W.toggleSet(index, i)} aria-label="Mark set done">{set.isDone ? '✓' : ''}</button>
          </div>
        ))}
        <div class="gap8 mt8">
          <button class="btn secondary small" onClick={() => W.addSet(index, 'normal')}>＋ Set</button>
          <button class="btn secondary small" onClick={() => W.addSet(index, 'warmup')}>＋ Warm-up</button>
          <button class="btn secondary small" onClick={() => W.addSet(index, 'drop')}>＋ Drop</button>
          {ex.sets.length > 1 && !ex.sets[ex.sets.length - 1].isDone && <button class="btn secondary small" onClick={() => W.removeSet(index, ex.sets.length - 1)}>− Last set</button>}
        </div>
        <div class="small faint mt8">Rest {fmtRest(ex.restBetweenSets)} between sets · {fmtRest(ex.restAfterExercise)} after this exercise</div>
      </div>
    </div>
  );
}

const EFFORT_HINTS = {
  1: 'Very easy', 2: 'Easy', 3: 'Easy', 4: 'Comfortable', 5: 'Moderate', 6: 'Moderate, 4+ reps left',
  7: 'Hard, 3 reps left', 8: 'Hard, 2 reps left', 9: 'Very hard, 1 rep left', 10: 'Max effort',
};

export function EffortSheet({ index, ex, onSave, onCancel }) {
  const [effort, setEffort] = useState(ex.effort ?? 7);
  const [injured, setInjured] = useState(ex.injured);
  const [note, setNote] = useState(ex.injuryNote || '');
  const save = onSave || ((e, i, n) => W.submitEffort(index, e, i, n));
  const cancel = onCancel || (() => W.cancelEffort());
  return (
    <Sheet onClose={cancel}>
      <h3>How hard was {ex.name}?</h3>
      <p class="small muted">Effort drives your next progressive overload suggestion.</p>
      <div class="effort-grid">
        {[1, 2, 3, 4, 5, 6, 7, 8, 9, 10].map((n) => <button key={n} class={n === effort ? 'on' : ''} onClick={() => setEffort(n)}>{n}</button>)}
      </div>
      <div class="center small muted mt8">{effort}/10 · {EFFORT_HINTS[effort]}</div>
      <div class="toggle mt8">
        <div class="col"><span>⚠︎ Injured or pain</span><span class="small muted">Next time suggests a lighter load</span></div>
        <button class={`switch ${injured ? 'on' : ''}`} style={injured ? { background: 'var(--red)', borderColor: 'var(--red)' } : null} onClick={() => setInjured(!injured)} />
      </div>
      {injured && <textarea rows="2" placeholder="What hurts? (optional)" value={note} onInput={(e) => setNote(e.currentTarget.value)} />}
      <div class="row mt16">
        <button class="btn secondary" onClick={cancel}>Not now</button>
        <button class="btn" onClick={() => save(effort, injured, note)}>Save</button>
      </div>
    </Sheet>
  );
}

function useWakeLock(enabled) {
  useEffect(() => {
    if (!enabled || !('wakeLock' in navigator)) return;
    let lock = null;
    const acquire = async () => {
      try { if (document.visibilityState === 'visible') lock = await navigator.wakeLock.request('screen'); } catch { /* not allowed here */ }
    };
    acquire();
    document.addEventListener('visibilitychange', acquire);
    return () => { document.removeEventListener('visibilitychange', acquire); lock?.release?.().catch(() => {}); };
  }, [enabled]);
}

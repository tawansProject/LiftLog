import { ENV_LABEL, COMMIT } from '../lib/env.js';
import { AccountCard } from './Account.jsx';
import { accountsEnabled } from '../lib/supabase.js';
import { useEffect, useState } from 'preact/hooks';
import { useStore, setState, updateSettings, exportBackup, importBackup } from '../lib/store.js';
import { push, toast } from '../nav.js';
import { Stepper, Toggle, Segmented, Page, TopBar } from '../components.jsx';
import { enableAlerts, sendTest, isStandalone, isIOS, pushSupported } from '../lib/push.js';
import { downloadLibrary, deleteLibrary, loadLibrary } from '../lib/exercisedb.js';
import { rest } from '../lib/format.js';

export function SettingsTab() {
  const s = useStore();
  const st = s.settings;
  const [busy, setBusy] = useState(null);
  const [lib, setLib] = useState(null);
  useEffect(() => { loadLibrary().then((l) => setLib(l ? l.length : 0)); }, []);

  const turnOnAlerts = async () => {
    setBusy('alerts');
    try {
      const sub = await enableAlerts();
      setState({ pushSubscription: sub });
      updateSettings({ restAlerts: true });
      toast('Rest alerts are on');
    } catch (e) { alert(e.message); } finally { setBusy(null); }
  };
  const test = async () => {
    setBusy('test');
    try { await sendTest(s.pushSubscription); toast('Test alert coming in 5 seconds. Lock your iPhone now.'); } catch (e) { alert(e.message); } finally { setBusy(null); }
  };
  const download = async () => {
    setBusy('lib');
    try { const n = await downloadLibrary((done, total) => setLib(`${done}/${total}`)); setLib(n); toast(`${n} exercises saved for offline use`); } catch (e) { alert(e.message); setLib(0); } finally { setBusy(null); }
  };
  const doExport = () => {
    const blob = new Blob([exportBackup()], { type: 'application/json' });
    const file = new File([blob], `liftlog-backup-${new Date().toISOString().slice(0, 10)}.json`, { type: 'application/json' });
    if (navigator.canShare?.({ files: [file] })) { navigator.share({ files: [file] }).catch(() => {}); return; }
    const a = document.createElement('a'); a.href = URL.createObjectURL(blob); a.download = file.name; a.click();
  };
  const doImport = (e) => {
    const f = e.currentTarget.files?.[0];
    if (!f) return;
    f.text().then((t) => {
      if (!confirm('Replace everything in LiftLog with this backup?')) return;
      try { importBackup(t); toast('Backup restored'); } catch (err) { alert(err.message); }
    });
  };

  return (
    <div class="screen">
      <h1>Settings</h1>
      {!isStandalone() && (
        <div class="note warn mb8">
          <b>Install LiftLog:</b> in Safari tap Share → <b>Add to Home Screen</b>, then open LiftLog from the Home Screen. Rest alerts and Apple Watch alerts only work from there.
        </div>
      )}

      <h2>Account</h2>
      <AccountCard />

      <h2>Apple Watch</h2>
      <div class="card">
        <p class="small">LiftLog sends rest alerts as iPhone notifications. When your iPhone is locked and you wear your Watch, they tap your wrist and show the next set.</p>
        {s.pushSubscription
          ? <>
              <Toggle label="Rest alerts" sub="Between sets and between exercises" on={st.restAlerts} onChange={(v) => updateSettings({ restAlerts: v })} />
              <button class="btn secondary small" disabled={busy} onClick={test}>{busy === 'test' ? 'Sending…' : 'Send a test alert'}</button>
            </>
          : <button class="btn" disabled={busy || (isIOS() && !isStandalone()) || !pushSupported()} onClick={turnOnAlerts}>{busy === 'alerts' ? 'Turning on…' : 'Turn on rest alerts'}</button>}
        <button class="link mt8" onClick={() => push({ type: 'watchGuide' })}>How LiftLog works with Apple Watch ›</button>
      </div>

      <h2>Rest defaults</h2>
      <div class="card">
        <div class="row between mb8"><span>Between sets</span><Stepper value={st.restBetweenSets} step={15} min={0} unit="s" onChange={(v) => updateSettings({ restBetweenSets: v })} /></div>
        <div class="row between"><span>Between exercises</span><Stepper value={st.restAfterExercise} step={15} min={0} unit="s" onChange={(v) => updateSettings({ restAfterExercise: v })} /></div>
        <div class="small faint mt8">Used for new exercises ({rest(st.restBetweenSets)} / {rest(st.restAfterExercise)}). Each exercise can have its own.</div>
      </div>

      <h2>Workout</h2>
      <div class="card">
        <div class="row between"><span>Weekly goal</span><Stepper value={st.weeklyGoal} min={1} unit="/wk" onChange={(v) => updateSettings({ weeklyGoal: Math.min(7, Math.max(1, v)) })} /></div>
        <Toggle label="Update plan after a session" sub="Saves what you actually lifted as the plan's next starting point" on={st.updateTemplateAfterWorkout} onChange={(v) => updateSettings({ updateTemplateAfterWorkout: v })} />
        <Toggle label="Keep screen awake" sub="During a workout" on={st.keepAwake} onChange={(v) => updateSettings({ keepAwake: v })} />
        <Toggle label="Beep when rest ends" sub="While LiftLog is open" on={st.sound} onChange={(v) => updateSettings({ sound: v })} />
      </div>

      <h2>You (for calories)</h2>
      <div class="card">
        <div class="row between mb8"><span>Body weight</span><Stepper value={st.bodyWeightKg} decimals step={0.5} unit="kg" onChange={(v) => updateSettings({ bodyWeightKg: v })} /></div>
        <div class="row between mb8"><span>Age</span><Stepper value={st.age} unit="yrs" onChange={(v) => updateSettings({ age: v })} /></div>
        <Segmented options={[['male', 'Male'], ['female', 'Female']]} value={st.sex} onChange={(v) => updateSettings({ sex: v })} />
      </div>

      <h2>Exercise Library</h2>
      <div class="card">
        <p class="small muted">About 1,500 exercises with animations. Search works online; download it to also search offline.</p>
        {typeof lib === 'number' && lib > 0
          ? <div class="row between"><span class="small">{lib} exercises saved</span><button class="link danger" onClick={async () => { await deleteLibrary(); setLib(0); }}>Remove</button></div>
          : <button class="btn secondary small" disabled={busy} onClick={download}>{busy === 'lib' ? `Downloading ${lib}…` : 'Download full library'}</button>}
      </div>

      <h2>Your data</h2>
      <div class="card">
        <p class="small muted">{accountsEnabled
          ? 'Stored on this iPhone, and in your account when you’re signed in. A backup file is an extra copy you control.'
          : 'Everything is stored on this iPhone only. Export a backup now and then.'}</p>
        <div class="gap8">
          <button class="btn secondary small" onClick={doExport}>Export backup</button>
          <label class="btn secondary small">Import backup<input type="file" accept="application/json,.json" style={{ display: 'none' }} onChange={doImport} /></label>
        </div>
        <div class="small faint mt8">{s.templates.length} workout plans · {s.records.length} sessions</div>
      </div>
      <p class="center tiny faint mt16">LiftLog web 1.1 · {ENV_LABEL}{COMMIT ? ` · ${COMMIT}` : ''}</p>
    </div>
  );
}

export function WatchGuide() {
  return (
    <Page>
      <TopBar title="Apple Watch" />
      <h2>What works</h2>
      <div class="card">
        <p><b>Rest alerts on your wrist.</b> When a rest ends, LiftLog sends a notification with your next set ("Bench press: set 2 of 4, 12 reps @ 30 kg"). With your iPhone locked, it taps your Watch.</p>
        <p class="small muted">If alerts show on the iPhone but not the Watch: Watch app on iPhone → Notifications → make sure "Mirror iPhone Alerts" is on for LiftLog.</p>
      </div>
      <div class="card">
        <p><b>Heart rate and calories.</b> Start "Traditional Strength Training" in the Watch's Workout app when you start in LiftLog. Your Watch records heart rate and calories to Apple Health as usual. After the workout, tap the calories box on the summary and type in the Watch's active calories and average heart rate.</p>
        <p class="small muted">Without that, LiftLog estimates calories from workout time and your body weight.</p>
      </div>
      <h2>What a web app can't do</h2>
      <div class="card">
        <p class="small">Apple Watch has no web browser and only runs apps installed from the App Store or Xcode, so LiftLog can't show its own screen or a "Done" button on the Watch. Web apps also can't read Apple Health, so heart rate can't be pulled in automatically.</p>
        <p class="small muted">Mark sets done on the iPhone. The Watch is for rest alerts and tracking heart rate.</p>
      </div>
    </Page>
  );
}

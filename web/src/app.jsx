import { useEffect, useState } from 'preact/hooks';
import { useStore } from './lib/store.js';
import { useNav, setTab, setToaster } from './nav.js';
import { Icon } from './components.jsx';
import { SessionsTab, TemplateDetail, Builder, Review, GifPage } from './views/Sessions.jsx';
import { Search, ExerciseConfig, CustomExercise } from './views/Search.jsx';
import { LiveWorkout } from './views/Workout.jsx';
import { RecordView } from './views/Summary.jsx';
import { ProgressTab } from './views/Progress.jsx';
import { HistoryTab } from './views/History.jsx';
import { SettingsTab, WatchGuide } from './views/Settings.jsx';
import { unlockAudio } from './lib/sound.js';

const TABS = [['workouts', 'Workouts'], ['progress', 'Progress'], ['history', 'Sessions'], ['settings', 'Settings']];

const PAGES = {
  template: TemplateDetail, builder: Builder, review: Review, search: Search, config: ExerciseConfig,
  custom: CustomExercise, record: RecordView, gif: GifPage, watchGuide: WatchGuide,
};

export function App() {
  const s = useStore();
  const nav = useNav();
  const [msg, setMsg] = useState(null);
  useEffect(() => {
    setToaster((m) => { setMsg(m); setTimeout(() => setMsg(null), 2600); });
    const unlock = () => unlockAudio();
    document.addEventListener('touchend', unlock, { once: true });
    document.addEventListener('click', unlock, { once: true });
  }, []);
  useEffect(() => { window.scrollTo(0, 0); }, [nav.tab]);

  const Tab = { workouts: SessionsTab, progress: ProgressTab, history: HistoryTab, settings: SettingsTab }[nav.tab];
  return (
    <>
      <Tab />
      <nav class="tabbar"><div>
        {TABS.map(([k, label]) => (
          <button key={k} class={nav.tab === k ? 'on' : ''} onClick={() => setTab(k)}><Icon name={k} />{label}</button>
        ))}
      </div></nav>
      {s.active && !s.workoutHidden && <LiveWorkout />}
      {nav.stack.map((p) => { const P = PAGES[p.type]; return <P {...p} key={p.key} />; })}
      {s.lastFinishedId && <RecordView id={s.lastFinishedId} justFinished />}
      {msg && <div class="toast">{msg}</div>}
    </>
  );
}

# LiftLog: personal strength-training app for iPhone + Apple Watch

> **The current app is the web app in [`web/`](web/README.md)** (installable on iPhone, rest alerts on Apple Watch).
> The native SwiftUI code below is paused and kept for reference.

Native SwiftUI app (iOS 17+, watchOS 10+) with a dark blue theme (`Views/Components/Theme.swift`; exercise GIFs on every session preview, tap one to enlarge). Local storage with SwiftData, iPhone ⇄ Watch sync with
WatchConnectivity, heart rate and calories from HealthKit, rest alerts with local notifications.
Exercise data comes from [ExerciseDB](https://github.com/ExerciseDB/exercisedb-api) (free hosted API, no key).

## Run it

1. Open `FitnessApp.xcodeproj` in **Xcode 16 or newer** (the project uses folder-synced groups, so
   every `.swift` file in the folders is picked up automatically).
2. Project settings → target **FitnessApp** → *Signing & Capabilities* → choose your Team. Do the same
   for **FitnessWatch**.
3. If Xcode says the bundle id is taken, change `BUNDLE_ID_PREFIX` (Project → Build Settings, search
   "BUNDLE_ID_PREFIX") from `com.tawan` to something unique. It updates the iPhone id, the Watch id and
   the companion link together.
4. Pick the **FitnessApp** scheme and your iPhone, press Run. The Watch app installs with it
   (or open the Watch app on the iPhone → Available Apps → Install).
5. On first launch allow Apple Health and notifications.

If signing fails on the HealthKit capability (this can happen with a free Apple ID), remove HealthKit from
both targets under Signing & Capabilities. The app still works; calories then use the duration-based estimate.

The Simulator works for everything except real heart rate. For the Watch in the Simulator, use a paired
iPhone + Watch simulator pair.

If the project ever fails to open, `project.yml` can regenerate it with XcodeGen
(`brew install xcodegen && xcodegen`).

## How it works

| Requirement | Where |
|---|---|
| 1, 14 Sessions with many exercises, unlimited saved sessions | `Views/Sessions/SessionListView.swift`, `SessionBuilderView.swift`, `Models/Persistence.swift` (`SessionTemplate`) |
| 13 Flow: create → search → target muscles → sets/reps/rest → more → confirm (muscle overview) → focus on current exercise → done + effort → finish (early allowed) → summary | `SessionBuilderView` → `ExerciseSearchView` → `ExerciseConfigView` → `ReviewSessionView` → `Views/Workout/LiveWorkoutView` → `EffortSheet` → `WorkoutSummaryView` |
| 2 Total-time counter (counts up, no limit) | `LiveWorkoutView` header (`ElapsedHeader`), Watch header |
| 3, 15 Rest between sets and between exercises + notification | `Workout/WorkoutEngine.swift` (`startRest`), `Services/NotificationManager.swift`, Watch haptic in `WatchSessionStore` |
| 4 Records / history | `Views/History/HistoryListView.swift` (Dashboard / List). The dashboard (`HistoryDashboardView.swift`) shows line graphs of volume, time, calories and effort for 1M/3M/6M/1Y, plus strength progress (top weight and estimated 1RM) per exercise |
| 5, 19 Progressive overload driven by effort + injured | `Services/ProgressionEngine.swift` (rules documented at the top of the file) |
| 6 Streak calendar | `Views/Progress/ProgressTabView.swift` (`StreakCalendarView`, `StreakHeader`) |
| 7 Muscle overview when creating | `ReviewSessionView` + `MuscleOverview` component, `Services/MuscleGroups.swift` |
| 8 Weekly / monthly summary | `PeriodSummaryView`, `Services/StatsCalculator.swift` |
| 9 Watch: current set, mark done, rest time, effort + injured after each exercise (Digital Crown) | `FitnessWatch/Views/WatchRootView.swift` |
| 10 ExerciseDB | `Services/ExerciseDBClient.swift` (`https://oss.exercisedb.dev/api/v1`) |
| 11 Calories from Health / heart rate | `Services/HealthKitManager.swift` (`estimateCalories`), Watch `WatchWorkoutManager` |
| 12, 18 Effort (1-10) and "injured" after each exercise | `Views/Workout/EffortSheet.swift` (editable later from the summary) |
| 16 Warm-up / normal / drop sets | `SetKind` in `Shared/WorkoutModels.swift`, set editors |
| 17 Previous record pre-filled | `HistoryService.prefill` when adding an exercise; the session is updated after each workout (Settings toggle); starting a session pulls in any newer record of the same exercise from another session (`WorkoutEngine.start`) |

### Progressive overload rules (`ProgressionEngine`)

Uses the last 5 logs of the exercise, newest first:

- **Injured last time** → about 20% lighter (bodyweight: about 30% fewer reps). Injured in 2 of the last 3 → also suggests swapping or resting the exercise.
- **All working sets hit target reps**: effort ≤5 → +2 weight steps; 6-7 → +1 step; 8 → +1 rep per set (add weight once at 15 reps); 9-10 → repeat. First clean session after an injury → at most one small step.
- **Missed reps**: ≥85% of target reps → repeat; less → about 10% lighter.
- **Stalled** (same top weight 3 sessions, never hitting target) → 10% deload.
- Weight step: 2 kg for dumbbells/kettlebells, 2.5 kg otherwise. Warm-up and drop sets scale with the top set.

### Calories

1. Active energy recorded by Apple Watch during the workout (the iPhone starts a Watch workout session automatically).
2. Otherwise average heart rate from Health with the Keytel (2005) formula, using weight/age/sex from Health or Settings.
3. Otherwise a 5-MET strength-training estimate.

### ExerciseDB

The free tier (`oss.exercisedb.dev`) has about 1,500 exercises with GIFs, no API key, 25 results per page.
Search uses `/exercises?name=…&bodyParts=…`; picked exercises are cached on the phone, and Settings has
"Download full library" for offline search. You can also create custom exercises. The ExerciseDB GitHub
repo is AGPL-3.0 and its data terms aren't published on the free tier, so this setup is fine for personal
use; check their terms before publishing to the App Store.

## What was verified

Built in a Linux container without Xcode, so it has **not been compiled or run yet**. Checked: the
`project.pbxproj` parses and every object reference resolves; the ExerciseDB endpoints and JSON shapes
were tested live; code was reviewed by hand against the iOS 17 / watchOS 10 APIs. Expect possibly a few
small compile fixes on the first build in Xcode.

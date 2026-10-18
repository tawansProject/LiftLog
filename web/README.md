# LiftLog web app

The LiftLog strength-training app as an installable web app (PWA) for iPhone, with rest alerts that
reach Apple Watch. It replaces the native SwiftUI app in the repo root, which is kept for reference.

- **Stack:** Vite + Preact. Local-first: sessions, history and settings live on the phone (localStorage;
  the downloaded Exercise Library in IndexedDB), with backup export/import. Signed-in users also sync to
  Supabase (email + password); see [`docs/ACCOUNTS.md`](../docs/ACCOUNTS.md).
- **Hosting:** Vercel (project root directory `web`). Functions in `api/`:
  - `api/exercises.js` proxies the free hosted exercise API (`oss.exercisedb.dev/api/v1`, no key) and caches it.
  - `api/push/schedule.js` waits until a rest ends and sends a Web Push; `api/push/key.js` serves the public key.
    Skipping, replacing or ending a rest posts `{ cancel: restId }` to the same function; it's recorded in Vercel's
    runtime cache and the waiting job checks it before sending, so cancelled alerts never arrive.
  - Env vars: `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` (generate with `npx web-push generate-vapid-keys`).
- **Environments:** `main` → production, `staging` → staging URL, other branches → previews. See
  [`docs/ENVIRONMENTS.md`](../docs/ENVIRONMENTS.md).
- **Install on iPhone:** open the site in Safari → Share → Add to Home Screen → open from the Home Screen →
  Settings → Turn on rest alerts.

## Apple Watch and Health

- Web apps can't run on Apple Watch. Rest alerts are Web Push notifications (iOS 16.4+, Home Screen apps only);
  with the iPhone locked they mirror to the Watch like any other notification.
- Web apps can't read Apple Health. Calories: active calories / average heart rate typed in from the Watch's
  Workout app (Keytel 2005 formula for heart rate), otherwise a 5-MET estimate.

## Requirements map

| # | Where |
|---|---|
| 1, 14 workout plans (templates), unlimited | `views/Sessions.jsx` (`SessionsTab`, `Builder`), `lib/store.js` templates |
| Quick session vs workout plan | `SessionsTab` start cards, `store.startQuickWorkout`, empty state in `views/Workout.jsx`, `store.saveRecordAsPlan` (summary) |
| Front/back body map | `components.jsx` `BodyMap`, `lib/bodymap.js` |
| GIFs | `components.jsx` `Thumb` (https link → `/api/gif` proxy by id → tap to retry), `api/gif.js`, cached by `public/sw.js`; large in the workout, next one in the rest banner |
| 13 flow | Builder → `views/Search.jsx` (search, target muscles) → `ExerciseConfig` (sets/reps/rest, GIF) → `Review` (muscle overview) → `views/Workout.jsx` → `EffortSheet` → `views/Summary.jsx` |
| 2 total timer | `LiveWorkout` header |
| 3, 15 rest timers + alerts | `lib/store.js` (`startRest`), `lib/push.js`, `public/sw.js`, `api/push/schedule.js` |
| 4 history + line graphs | `views/History.jsx` |
| 5, 19 progressive overload | `lib/progression.js` |
| 6 streak calendar, 8 weekly/monthly | `views/Progress.jsx`, `lib/stats.js` |
| 7 muscle overview | `components.jsx` `MuscleOverview`, `lib/muscles.js` |
| 9 Watch | rest alerts (see above), guide in Settings |
| 10 exercise data | `lib/exercisedb.js`, `api/exercises.js` (shown as "Exercise Library") |
| 11 calories | `lib/calories.js`, summary calories editor |
| 12, 18 effort + injured | `EffortSheet` |
| 16 warm-up / drop sets | set type badge (tap to switch) |
| 17 previous record prefill | `lib/history.js` `prefill`, `startWorkout` |

## Develop

```
npm install
npm run dev      # /api/exercises is proxied to the live API; push needs a Vercel deploy
npm test         # overload rules, streaks, muscles, calories
npm run build
```

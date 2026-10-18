# Environments: production and staging

LiftLog's web app (`web/`) is hosted on Vercel (project `liftlog`, root directory `web`). Each
environment is a Git branch, so moving a change between environments is a merge.

| Environment | Git branch | URL | What it's for |
|---|---|---|---|
| **Production** | `main` | The project's production domain (Vercel → liftlog → Domains) | The app you use every day |
| **Staging** | `staging` | `https://liftlog-git-staging-tawansprojects-projects.vercel.app` (stable: always the latest `staging` build) | Try changes on your phone before they reach production |
| Preview | any other branch | `liftlog-git-<branch>-tawansprojects-projects.vercel.app` | One-off previews of a work-in-progress branch |

Non-production builds show a small badge at the top of the screen (**Staging · abc1234**, or
**Preview · branch**), and Settings shows the environment and build at the bottom. Production shows no
badge.

## How a change gets to production

1. Work happens on a feature branch (for example `claude/...`). Vercel builds a preview for it.
2. Merge the feature branch into **`staging`** (pull request into `staging`). Vercel redeploys the staging URL.
   The **Web app checks** workflow runs the tests and the build.
3. Open the staging URL on your iPhone and try it.
4. When it's good, merge **`staging` into `main`** (pull request `staging` → `main`). Vercel deploys production.

Urgent fix: a pull request straight into `main` works too. Afterwards merge `main` back into `staging`
so the two branches don't drift apart.

## Data is separate per environment

Workouts, plans and settings live in the browser's storage, which belongs to one web address. Staging and
production have different addresses, so **staging never touches your real data**. To try staging with real data,
use Settings → Export backup on production and Import backup on staging.

On iPhone, add each one to the Home Screen separately if you want both. Give them different names so you
can tell them apart, for example "LiftLog" and "LiftLog Staging".

## Environment variables (Vercel → liftlog → Settings → Environment Variables)

| Variable | Production | Preview (used by staging) |
|---|---|---|
| `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `VAPID_SUBJECT` | Needed for rest alerts | Optional. Without them staging works but rest alerts are off. Use a separate key pair from production (`npx web-push generate-vapid-keys`) |
| `SUPABASE_URL`, `SUPABASE_ANON_KEY` (or the `NEXT_PUBLIC_` versions), `POSTGRES_URL…` | From the `liftlog-prod` Supabase project | From the `liftlog-staging` Supabase project |

Vercel applies **Preview** variables to every non-production branch. To give staging its own values that other
previews don't get, add the variable to Preview and pick the `staging` branch in the "Git branch" field.

`VERCEL_ENV`, `VERCEL_GIT_COMMIT_REF` and `VERCEL_GIT_COMMIT_SHA` are set by Vercel automatically and are only
used to show the environment badge (`web/vite.config.js`, `web/src/lib/env.js`).

Accounts and sync: the Supabase variables are added by Vercel's Supabase integration. Setup steps are in
[`ACCOUNTS.md`](ACCOUNTS.md).

## Optional: nicer staging address

In Vercel → liftlog → Settings → Domains, add a domain (for example `liftlog-staging.vercel.app` if it's free,
or `staging.<your-domain>`) and set its **Git branch** to `staging`. The `liftlog-git-staging-…` URL keeps
working too.

## Production branch check

Vercel → liftlog → Settings → Git → **Production Branch** should be `main`. That's Vercel's default for this
repository, because `main` is its default branch.

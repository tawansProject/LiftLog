# Accounts and cloud sync (Supabase)

LiftLog stays local-first: everything works on the phone, offline too. When you're signed in, plans,
sessions and settings also sync to your account in the background, so they survive a reinstall and
show up on any device you sign in on. The workout in progress stays on the device until you finish it.

- Sign-in: email + password (Supabase Auth). Forgot password sends a reset link.
- Storage: one Supabase table, `liftlog_items` (`web/supabase/schema.sql`). Row-level security means
  each account can only read and write its own rows.
- The table is created and updated automatically on every Vercel build (`web/scripts/migrate.mjs`).
- Code: `web/src/lib/sync.js` (merge rules, tested in `web/tests/sync.test.js`), `web/src/lib/account.js`,
  `web/src/views/Account.jsx`.

Until Supabase is connected, Settings shows "Sign-in isn't set up" and the app keeps working on-device.

## One-time setup (about 10 minutes, all in the browser)

Staging and production each get their own Supabase project, so staging never touches your real data.
Supabase's free plan allows two projects.

### 1. Production database
1. Vercel → **liftlog** project → **Storage** → **Create Database** → **Supabase** → **Continue**.
2. Name it `liftlog-prod`, pick the region closest to you (or the one next to your Vercel functions), plan **Free**, **Create**.
3. In **Connect Project**: choose **liftlog**, tick **Production** only, untick Preview and Development,
   leave the prefix empty, **Connect**.

### 2. Staging database
1. Same again: **Storage** → **Create Database** → **Supabase**, name it `liftlog-staging`.
2. In **Connect Project**: choose **liftlog**, tick **Preview** only, **Connect**.
   If Vercel says a variable already exists, it means step 1 included Preview: open
   **Settings → Environment Variables**, set the `SUPABASE_*`, `NEXT_PUBLIC_SUPABASE_*` and `POSTGRES_*`
   variables from `liftlog-prod` to **Production** only, then connect `liftlog-staging` again.

### 3. Tell Supabase where the app lives (for the confirmation and reset emails)
For each project (Vercel → Storage → the database → **Open in Supabase**):
1. **Authentication → URL Configuration**.
2. **Site URL**: production → your production address (for example `https://liftlog-….vercel.app`);
   staging → `https://liftlog-git-staging-tawansprojects-projects.vercel.app`.
3. **Redirect URLs**: add the same address followed by `/**`.

### 4. Deploy
Redeploy once so the builds pick up the new variables: Vercel → **Deployments** → latest Production
deployment → **⋯ → Redeploy** (and the same for the latest `staging` deployment). The build log shows
`[migrate] Sync schema is up to date.`

### 5. Create your account
On the iPhone: LiftLog → **Settings → Account → Create account**. Supabase emails a confirmation link;
tap it (it opens in Safari, that's fine), then come back to the LiftLog app and **Sign in**. Everything
already on the phone uploads on the first sign-in.

## Notes
- Supabase's built-in email sender is limited to a few emails an hour, which is plenty for one person.
  For more, add your own SMTP in Supabase → Authentication → Emails.
- To skip the confirmation email: Supabase → Authentication → Sign In / Providers → Email → turn off
  **Confirm email**.
- Signing out removes the data from that device; it stays in the account. A backup file
  (Settings → Export backup) is still a good extra copy.
- If the same plan or session is edited on two devices before either syncs, the device that syncs
  last keeps its version.

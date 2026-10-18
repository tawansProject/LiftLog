-- LiftLog cloud sync. Safe to run any number of times (scripts/migrate.mjs runs it on
-- every Vercel build). One row per synced item: a workout plan, a session (workout
-- record) or the settings. Deleted items stay as tombstones so other devices delete them too.

create table if not exists public.liftlog_items (
  user_id    uuid        not null default auth.uid() references auth.users (id) on delete cascade,
  kind       text        not null check (kind in ('template', 'record', 'settings')),
  id         text        not null check (char_length(id) between 1 and 100),
  data       jsonb,
  deleted    boolean     not null default false,
  updated_at timestamptz not null default now(),
  primary key (user_id, kind, id)
);

create index if not exists liftlog_items_user_updated on public.liftlog_items (user_id, updated_at);

-- updated_at is the server's clock, so devices can ask "what changed since X".
create or replace function public.liftlog_touch() returns trigger
language plpgsql set search_path = '' as $$
begin
  new.updated_at := now();
  return new;
end $$;

drop trigger if exists liftlog_items_touch on public.liftlog_items;
create trigger liftlog_items_touch before insert or update on public.liftlog_items
  for each row execute function public.liftlog_touch();

-- Each signed-in user sees and changes only their own rows.
alter table public.liftlog_items enable row level security;

drop policy if exists "own rows: select" on public.liftlog_items;
create policy "own rows: select" on public.liftlog_items for select to authenticated
  using ((select auth.uid()) = user_id);

drop policy if exists "own rows: insert" on public.liftlog_items;
create policy "own rows: insert" on public.liftlog_items for insert to authenticated
  with check ((select auth.uid()) = user_id);

drop policy if exists "own rows: update" on public.liftlog_items;
create policy "own rows: update" on public.liftlog_items for update to authenticated
  using ((select auth.uid()) = user_id) with check ((select auth.uid()) = user_id);

grant select, insert, update on public.liftlog_items to authenticated;
revoke all on public.liftlog_items from anon;

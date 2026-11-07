-- StandPoint · Step 4: security hardening and scale (Nov 7, 2026)
-- Paste into Supabase → SQL Editor → New query → Run, after 01–03. Run it BEFORE pushing the app update that needs it.
-- Safe to run once. It rotates every club's join code (testers get new codes from their club's Invite card).

-- 1. Version numbers on shared rows, so two coaches saving at once can't wipe each other's changes,
--    and the app only downloads rows that changed since it last looked.
alter table org_state     add column if not exists rev bigint not null default 0;
alter table org_private   add column if not exists rev bigint not null default 0;
alter table player_plans  add column if not exists rev bigint not null default 0;
alter table player_state  add column if not exists rev bigint not null default 0;

create or replace function bump_rev() returns trigger language plpgsql as $$
begin
  new.rev := old.rev + 1;
  return new;
end; $$;
drop trigger if exists bump_rev on org_state;    create trigger bump_rev before update on org_state    for each row execute function bump_rev();
drop trigger if exists bump_rev on org_private;  create trigger bump_rev before update on org_private  for each row execute function bump_rev();
drop trigger if exists bump_rev on player_plans; create trigger bump_rev before update on player_plans for each row execute function bump_rev();
drop trigger if exists bump_rev on player_state; create trigger bump_rev before update on player_state for each row execute function bump_rev();

-- 2. Size limits, so one account can't stuff a row and slow down everyone who loads it
alter table player_state   drop constraint if exists player_state_size;   alter table player_state   add constraint player_state_size   check (octet_length(data::text) <= 1000000);
alter table player_private drop constraint if exists player_private_size; alter table player_private add constraint player_private_size check (octet_length(data::text) <= 1000000);
alter table player_plans   drop constraint if exists player_plans_size;   alter table player_plans   add constraint player_plans_size   check (octet_length(data::text) <= 500000);
alter table org_state      drop constraint if exists org_state_size;      alter table org_state      add constraint org_state_size      check (octet_length(data::text) <= 2000000);
alter table org_private    drop constraint if exists org_private_size;    alter table org_private    add constraint org_private_size    check (octet_length(data::text) <= 2000000);
alter table profiles       drop constraint if exists profiles_name_size;  alter table profiles       add constraint profiles_name_size  check (char_length(display_name) <= 80);
alter table orgs           drop constraint if exists orgs_name_size;      alter table orgs           add constraint orgs_name_size      check (char_length(name) <= 80 and char_length(type) <= 40);
alter table memberships    drop constraint if exists memberships_team_size; alter table memberships  add constraint memberships_team_size check (team_id is null or char_length(team_id) <= 64);

-- 3. Columns people can change. Everything else (ids, owners, join codes, created dates) only changes through the functions below.
revoke update on orgs from anon, authenticated;
grant update (name, type, auto_accept) on orgs to authenticated;
revoke update on memberships from anon, authenticated;
grant update (status, team_id, role) on memberships to authenticated;
revoke update on profiles from anon, authenticated;
grant update (display_name, is_coach, age_ok) on profiles to authenticated;
revoke update on player_plans from anon, authenticated;
grant update (org_id, player_id, data, updated_at, updated_by) on player_plans to authenticated;  -- the app saves plans with an upsert
revoke update on org_state from anon, authenticated;
grant update (data, updated_at, updated_by) on org_state to authenticated;
revoke update on org_private from anon, authenticated;
grant update (data, updated_at) on org_private to authenticated;
revoke update on player_state from anon, authenticated;
grant update (data, updated_at) on player_state to authenticated;
revoke update on player_private from anon, authenticated;
grant update (data, updated_at) on player_private to authenticated;

-- Only an admin changes someone's role
create or replace function guard_membership() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role <> old.role and not is_admin(old.org_id) then raise exception 'Only a club admin can change roles'; end if;
  return new;
end; $$;
drop trigger if exists guard_membership on memberships;
create trigger guard_membership before update on memberships for each row execute function guard_membership();

-- A plan stays with its club and its player
create or replace function guard_plan() returns trigger language plpgsql as $$
begin
  if new.org_id <> old.org_id or new.player_id <> old.player_id then raise exception 'A plan cannot move to another club or player'; end if;
  return new;
end; $$;
drop trigger if exists guard_plan on player_plans;
create trigger guard_plan before update on player_plans for each row execute function guard_plan();

-- A coach can only write a plan for someone who is in the club
drop policy if exists "coaches change his plan" on player_plans;
create policy "coaches change his plan" on player_plans for update using (is_coach(org_id)) with check (
  is_coach(org_id) and exists (select 1 from memberships m where m.org_id = player_plans.org_id and m.user_id = player_plans.player_id));

-- 4. Stronger join codes: 8 characters, no look-alikes (0/O, 1/I/L), from a secure random source
create or replace function make_join_code() returns text language plpgsql volatile set search_path = public as $$
declare
  abc text := 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  h text; code text; i int;
begin
  loop
    h := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
    code := '';
    for i in 0..7 loop
      code := code || substr(abc, (('x' || substr(h, i * 8 + 1, 8))::bit(32)::bigint % 31)::int + 1, 1);
    end loop;
    exit when not exists (select 1 from orgs where join_code = code);
  end loop;
  return code;
end; $$;

update orgs set join_code = make_join_code();

-- An admin can get a new code (the old one stops working)
create or replace function new_join_code(o uuid) returns text language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if not is_admin(o) then raise exception 'Only a club admin can change the code'; end if;
  c := make_join_code();
  update orgs set join_code = c where id = o;
  return c;
end; $$;

-- 5. Slow down code guessing: 20 wrong tries an hour per account, then wait
create table if not exists join_attempts (
  user_id uuid not null references auth.users(id) on delete cascade,
  at timestamptz not null default now()
);
create index if not exists join_attempts_user_at on join_attempts (user_id, at);
alter table join_attempts enable row level security;   -- no policies: only the functions below touch it

create or replace function clean_code(code text) returns text language sql immutable as $$
  select upper(regexp_replace(coalesce(code, ''), '[^A-Za-z0-9]', '', 'g'));
$$;

create or replace function check_join_tries() returns void language plpgsql security definer set search_path = public as $$
begin
  if (select count(*) from join_attempts where user_id = auth.uid() and at > now() - interval '1 hour') >= 20 then
    raise exception 'Too many wrong codes. Wait an hour and try again, or ask your coach to check the code.';
  end if;
end; $$;

create or replace function create_org(org_name text, org_type text default 'Training facility')
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not exists (select 1 from profiles where id = auth.uid() and age_ok) then raise exception 'Confirm you are 13 or older first.'; end if;
  if char_length(trim(coalesce(org_name, ''))) = 0 then raise exception 'Give your club a name.'; end if;
  insert into orgs (name, type, join_code, created_by)
    values (left(trim(org_name), 80), left(coalesce(org_type, 'Training facility'), 40), make_join_code(), auth.uid())
    returning id into new_id;
  insert into memberships (org_id, user_id, role, status) values (new_id, auth.uid(), 'admin', 'active');
  insert into org_state (org_id) values (new_id);
  insert into org_private (org_id) values (new_id);
  return new_id;
end; $$;

create or replace function org_teams(code text)
returns jsonb language plpgsql volatile security definer set search_path = public as $$
declare o uuid; r jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  perform check_join_tries();
  select id into o from orgs where join_code = clean_code(code);
  if o is null then insert into join_attempts (user_id) values (auth.uid()); return '[]'::jsonb; end if;
  select coalesce(jsonb_agg(jsonb_build_object('id', t->>'id', 'name', t->>'name')), '[]'::jsonb) into r
    from org_state s, jsonb_array_elements(coalesce(s.data->'teams', '[]'::jsonb)) t where s.org_id = o;
  return r;
end; $$;

create or replace function join_org(code text, as_role text default 'player', team text default null)
returns text language plpgsql security definer set search_path = public as $$
declare o orgs%rowtype; st text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if as_role not in ('player', 'coach') then raise exception 'Unknown role'; end if;
  if not exists (select 1 from profiles where id = auth.uid() and age_ok) then raise exception 'Confirm you are 13 or older first.'; end if;
  perform check_join_tries();
  select * into o from orgs where join_code = clean_code(code);
  if not found then insert into join_attempts (user_id) values (auth.uid()); return 'bad_code'; end if;
  if exists (select 1 from memberships where org_id = o.id and user_id = auth.uid()) then return 'already'; end if;
  st := case when o.auto_accept and as_role = 'player' then 'active' else 'pending' end;
  insert into memberships (org_id, user_id, role, status, team_id) values (o.id, auth.uid(), as_role, st, left(team, 64));
  return st;
end; $$;

revoke execute on function create_org(text, text), join_org(text, text, text), org_teams(text), new_join_code(uuid),
  make_join_code(), check_join_tries() from anon, public;
grant execute on function create_org(text, text), join_org(text, text, text), org_teams(text), new_join_code(uuid) to authenticated;

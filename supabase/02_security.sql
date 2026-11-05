-- StandPoint version 1 · Step 3: security rules and functions
-- Paste into Supabase → SQL Editor → New query → Run, after 01_tables.sql.

-- 1. Turn on row level security: with it on, nobody sees a row unless a rule below allows it
alter table profiles enable row level security;
alter table orgs enable row level security;
alter table memberships enable row level security;
alter table org_state enable row level security;
alter table org_private enable row level security;
alter table player_plans enable row level security;
alter table player_state enable row level security;
alter table player_private enable row level security;

-- 2. Helper checks the rules use
create or replace function is_member(o uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
    where org_id = o and user_id = auth.uid() and status = 'active');
$$;

create or replace function is_coach(o uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
    where org_id = o and user_id = auth.uid() and status = 'active' and role in ('admin', 'coach'));
$$;

create or replace function is_admin(o uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from memberships
    where org_id = o and user_id = auth.uid() and status = 'active' and role = 'admin');
$$;

-- Am I a coach in a club this player belongs to (or asked to join)?
create or replace function coaches_player(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (
    select 1 from memberships pl join memberships co on co.org_id = pl.org_id
    where pl.user_id = p and pl.role = 'player' and pl.status in ('pending', 'active')
      and co.user_id = auth.uid() and co.status = 'active' and co.role in ('admin', 'coach'));
$$;

-- Can I see this person's name? Yourself, your players, or your coaches. Players never see other players.
create or replace function can_see_profile(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select p = auth.uid() or exists (
    select 1 from memberships me join memberships them on them.org_id = me.org_id
    where me.user_id = auth.uid() and them.user_id = p and me.status = 'active'
      and (me.role in ('admin', 'coach') or them.role in ('admin', 'coach')));
$$;

-- 3. The rules
create policy "see allowed profiles" on profiles for select using (can_see_profile(id));
create policy "edit my profile" on profiles for update using (id = auth.uid()) with check (id = auth.uid());

create policy "members see their club" on orgs for select using (is_member(id) or created_by = auth.uid());
create policy "coaches edit the club" on orgs for update using (is_coach(id)) with check (is_coach(id));
create policy "admins delete the club" on orgs for delete using (is_admin(id));

create policy "see my membership, coaches see all" on memberships for select using (user_id = auth.uid() or is_coach(org_id));
-- Coaches accept and move players; only an admin can change or remove a coach
create policy "coaches accept and move players" on memberships for update
  using (is_admin(org_id) or (is_coach(org_id) and role = 'player'))
  with check (is_admin(org_id) or (is_coach(org_id) and role = 'player'));
create policy "coaches remove players, anyone leaves" on memberships for delete
  using (user_id = auth.uid() or is_admin(org_id) or (is_coach(org_id) and role = 'player'));

create policy "members read club data" on org_state for select using (is_member(org_id));
create policy "coaches change club data" on org_state for update using (is_coach(org_id)) with check (is_coach(org_id));

create policy "coaches only" on org_private for select using (is_coach(org_id));
create policy "coaches only, changes" on org_private for update using (is_coach(org_id)) with check (is_coach(org_id));

create policy "player and his coaches read his plan" on player_plans for select using (player_id = auth.uid() or is_coach(org_id));
create policy "coaches add his plan" on player_plans for insert with check (
  is_coach(org_id) and exists (select 1 from memberships m where m.org_id = player_plans.org_id and m.user_id = player_plans.player_id));
create policy "coaches change his plan" on player_plans for update using (is_coach(org_id)) with check (is_coach(org_id));
create policy "coaches remove his plan" on player_plans for delete using (is_coach(org_id));

create policy "player and his coaches read" on player_state for select using (user_id = auth.uid() or coaches_player(user_id));
create policy "only the player writes" on player_state for update using (user_id = auth.uid()) with check (user_id = auth.uid());

create policy "only the player" on player_private for select using (user_id = auth.uid());
create policy "only the player writes private" on player_private for update using (user_id = auth.uid()) with check (user_id = auth.uid());

-- 4. Actions that need more than one table, done safely in one step
-- Start a club: you become its admin
create or replace function create_org(org_name text, org_type text default 'Training facility')
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  insert into orgs (name, type, join_code, created_by)
    values (org_name, org_type, upper(substr(md5(random()::text || clock_timestamp()::text), 1, 6)), auth.uid())
    returning id into new_id;
  insert into memberships (org_id, user_id, role, status) values (new_id, auth.uid(), 'admin', 'active');
  insert into org_state (org_id) values (new_id);
  insert into org_private (org_id) values (new_id);
  return new_id;
end; $$;

-- The teams a player can pick when joining (names only)
create or replace function org_teams(code text)
returns jsonb language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t->>'id', 'name', t->>'name')), '[]'::jsonb)
  from orgs o join org_state s on s.org_id = o.id,
       jsonb_array_elements(coalesce(s.data->'teams', '[]'::jsonb)) t
  where o.join_code = upper(trim(code));
$$;

-- Join with a code: players wait for a coach unless the club accepts automatically; coaches always wait for an admin
create or replace function join_org(code text, as_role text default 'player', team text default null)
returns text language plpgsql security definer set search_path = public as $$
declare o orgs%rowtype; st text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if as_role not in ('player', 'coach') then raise exception 'Unknown role'; end if;
  select * into o from orgs where join_code = upper(trim(code));
  if not found then return 'bad_code'; end if;
  if exists (select 1 from memberships where org_id = o.id and user_id = auth.uid()) then return 'already'; end if;
  st := case when o.auto_accept and as_role = 'player' then 'active' else 'pending' end;
  insert into memberships (org_id, user_id, role, status, team_id) values (o.id, auth.uid(), as_role, st, team);
  return st;
end; $$;

-- Every new sign-in gets its own empty rows
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into profiles (id, display_name) values (new.id, coalesce(new.raw_user_meta_data->>'full_name', ''));
  insert into player_state (user_id) values (new.id);
  insert into player_private (user_id) values (new.id);
  return new;
end; $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

-- Signed-out visitors can't call the club functions
revoke execute on function create_org(text, text), join_org(text, text, text), org_teams(text) from anon, public;
grant execute on function create_org(text, text), join_org(text, text, text), org_teams(text) to authenticated;

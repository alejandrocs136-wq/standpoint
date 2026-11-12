-- StandPoint · Step 6: child safety and the launch review fixes (Nov 2026)
-- Paste into Supabase → SQL Editor → New query → Run, after 01–05. Safe to run more than once.
-- Run it BEFORE pushing the app update that goes with it, then push the app right away.
--
-- What it does:
--  1. Coaches see a player's data only when he's an active member of an approved club, and,
--     if he's under 18, a parent has approved. A pending request shows his name and team, nothing else.
--  2. Birthdates replace the "I'm 13 or older" checkbox. Coaches and club founders must be 18+.
--  3. Parent accounts: a parent links with the player's one-time family code, approves, and can pause
--     sharing or remove him from a club at any time.
--  4. StandPoint staff approve every new club before players can join it.
--  5. Sign-up is invite-only until we turn it off.
--  6. "Report a coach": reports go to StandPoint staff, who can suspend a coach everywhere.
--  7. Deleting an account can't wipe a club other people are in.
--  8. A club history nobody can edit or delete, written by the database itself.
--  9. The missing index on memberships.

-- ============ 0. StandPoint staff ============
create table if not exists sp_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  added_at timestamptz not null default now()
);
alter table sp_admins enable row level security;   -- no policies: only the functions below read it

create or replace function is_sp_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from sp_admins where user_id = auth.uid());
$$;

-- People StandPoint has blocked from starting or joining clubs (a reported coach, for example)
create table if not exists sp_blocked (
  user_id uuid primary key references auth.users(id) on delete cascade,
  reason text,
  at timestamptz not null default now()
);
alter table sp_blocked enable row level security;

-- ============ 1. Birthdates (kept apart from profiles so coaches never see them) ============
create table if not exists person_facts (
  user_id uuid primary key references auth.users(id) on delete cascade,
  birthdate date,
  updated_at timestamptz not null default now()
);
alter table person_facts enable row level security;
drop policy if exists "see my own facts" on person_facts;
create policy "see my own facts" on person_facts for select using (user_id = auth.uid());
revoke insert, update, delete on person_facts from anon, authenticated;

alter table profiles add column if not exists is_parent boolean not null default false;

create or replace function sp_date(t text) returns date language plpgsql immutable as $$
begin
  if t is null or t !~ '^\d{4}-\d{2}-\d{2}$' then return null; end if;
  return t::date;
exception when others then return null;
end; $$;

create or replace function is_adult(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select birthdate <= (current_date - interval '18 years')::date from person_facts where user_id = p), false);
$$;

create or replace function has_birthdate(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from person_facts where user_id = p and birthdate is not null);
$$;

-- ============ 2. Parents ============
create table if not exists parent_links (
  player_id uuid not null references auth.users(id) on delete cascade,
  parent_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'approved' check (status in ('approved', 'paused')),
  consent_version text,
  approved_at timestamptz,
  paused_at timestamptz,
  created_at timestamptz not null default now(),
  primary key (player_id, parent_id)
);
alter table parent_links enable row level security;
drop policy if exists "parent and player see the link" on parent_links;
create policy "parent and player see the link" on parent_links for select using (parent_id = auth.uid() or player_id = auth.uid());
revoke insert, update, delete on parent_links from anon, authenticated;

-- One-time code a player under 18 gives his parent
create table if not exists family_codes (
  player_id uuid primary key references auth.users(id) on delete cascade,
  code text unique not null,
  created_at timestamptz not null default now()
);
alter table family_codes enable row level security;
revoke all on family_codes from anon, authenticated;

create or replace function is_parent_of(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from parent_links where parent_id = auth.uid() and player_id = p);
$$;

-- Can his coaches see his data? Adults yes; under 18 only once a parent has approved and hasn't paused it.
create or replace function player_cleared(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select is_adult(p) or exists (select 1 from parent_links where player_id = p and status = 'approved');
$$;

-- ============ 3. Club approval and the new access rule ============
alter table orgs add column if not exists approved boolean not null default false;
alter table orgs add column if not exists approved_at timestamptz;
alter table orgs add column if not exists staff_notified_at timestamptz;   -- set by the notify-staff function

-- Only an active player in an approved club, cleared to share, and only to that club's active coaches.
-- (Before: pending requests counted too.)
create or replace function coaches_player(p uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select player_cleared(p) and exists (
    select 1 from memberships pl
      join memberships co on co.org_id = pl.org_id
      join orgs o on o.id = pl.org_id
    where pl.user_id = p and pl.role = 'player' and pl.status = 'active' and o.approved
      and co.user_id = auth.uid() and co.status = 'active' and co.role in ('admin', 'coach'));
$$;

-- Suspended: StandPoint can suspend a member; only StandPoint can restore one
alter table memberships drop constraint if exists memberships_status_check;
alter table memberships add constraint memberships_status_check check (status in ('pending', 'active', 'declined', 'suspended'));

create or replace function guard_membership() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.role <> old.role and not is_admin(old.org_id) and not is_sp_admin() then raise exception 'Only a club admin can change roles'; end if;
  if old.status = 'suspended' and new.status <> 'suspended' and not is_sp_admin() then raise exception 'Only StandPoint can restore a suspended account'; end if;
  if new.status = 'suspended' and old.status <> 'suspended' and not is_sp_admin() then raise exception 'Only StandPoint can suspend an account'; end if;
  return new;
end; $$;
drop trigger if exists guard_membership on memberships;
create trigger guard_membership before update on memberships for each row execute function guard_membership();

-- The index the review found missing: every "which clubs is this person in" lookup uses it
create index if not exists memberships_user_idx on memberships (user_id);

-- ============ 4. Profiles: who can change what ============
-- The age flag now comes only from the birthdate. People can still set their name and whether they coach or parent.
revoke update on profiles from anon, authenticated;
grant update (display_name, is_coach, is_parent) on profiles to authenticated;

-- ============ 5. Invite-only sign-up ============
create table if not exists app_settings (
  id int primary key default 1 check (id = 1),
  invite_only boolean not null default true
);
insert into app_settings (id) values (1) on conflict (id) do nothing;
alter table app_settings enable row level security;

create table if not exists signup_invites (
  email text primary key check (email = lower(email)),
  note text,
  added_by uuid references auth.users(id) on delete set null,
  added_at timestamptz not null default now()
);
alter table signup_invites enable row level security;

create or replace function sp_invite_gate() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if coalesce((select invite_only from app_settings where id = 1), true)
     and not exists (select 1 from signup_invites where email = lower(coalesce(new.email, ''))) then
    raise exception 'StandPoint is invite-only right now. Ask the person who invited you to add this email.';
  end if;
  return new;
end; $$;
drop trigger if exists sp_invite_gate on auth.users;
create trigger sp_invite_gate before insert on auth.users for each row execute function sp_invite_gate();

-- New accounts: name, parent or not, and the birthdate from the sign-up form. Under 13 can't sign up.
create or replace function handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
declare bd date := sp_date(new.raw_user_meta_data->>'birthdate');
begin
  if bd is not null and bd > (current_date - interval '13 years')::date then raise exception 'StandPoint is for ages 13 and up.'; end if;
  if bd is not null and bd < (current_date - interval '100 years')::date then bd := null; end if;
  insert into profiles (id, display_name, is_parent, age_ok)
    values (new.id, left(coalesce(new.raw_user_meta_data->>'full_name', ''), 80),
            coalesce(new.raw_user_meta_data->>'account_type', '') = 'parent', bd is not null);
  insert into player_state (user_id) values (new.id);
  insert into player_private (user_id) values (new.id);
  if bd is not null then insert into person_facts (user_id, birthdate) values (new.id, bd); end if;
  return new;
end; $$;

-- ============ 6. The club history nobody can edit ============
create table if not exists audit_log (
  id bigserial primary key,
  at timestamptz not null default now(),
  actor uuid,
  org_id uuid,
  action text not null,
  target uuid,
  detail jsonb not null default '{}'
);
create index if not exists audit_log_org on audit_log (org_id, id desc);
create index if not exists audit_log_recent on audit_log (org_id, target, action, at desc);
alter table audit_log enable row level security;
drop policy if exists "coaches read their club history" on audit_log;
create policy "coaches read their club history" on audit_log for select using ((org_id is not null and is_coach(org_id)) or is_sp_admin());
revoke insert, update, delete, truncate on audit_log from anon, authenticated;

create or replace function audit(o uuid, act text, tgt uuid, det jsonb) returns void
language sql security definer set search_path = public as $$
  insert into audit_log (actor, org_id, action, target, detail) values (auth.uid(), o, act, tgt, coalesce(det, '{}'::jsonb));
$$;

create or replace function audit_memberships() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform audit(new.org_id, 'member_joined', new.user_id, jsonb_build_object('role', new.role, 'status', new.status, 'team', new.team_id));
  elsif tg_op = 'UPDATE' then
    if new.status is distinct from old.status or new.role is distinct from old.role or new.team_id is distinct from old.team_id then
      perform audit(new.org_id, 'member_changed', new.user_id, jsonb_build_object('role', new.role, 'old_role', old.role, 'status', new.status, 'old_status', old.status, 'team', new.team_id, 'old_team', old.team_id));
    end if;
  else perform audit(old.org_id, 'member_removed', old.user_id, jsonb_build_object('role', old.role, 'status', old.status));
  end if;
  return null;
end; $$;
drop trigger if exists audit_memberships on memberships;
create trigger audit_memberships after insert or update or delete on memberships for each row execute function audit_memberships();

create or replace function audit_orgs() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'INSERT' then perform audit(new.id, 'club_created', null, jsonb_build_object('name', new.name, 'type', new.type));
  elsif tg_op = 'UPDATE' then
    if new.name is distinct from old.name or new.type is distinct from old.type or new.auto_accept is distinct from old.auto_accept or new.approved is distinct from old.approved then
      perform audit(new.id, 'club_changed', null, jsonb_build_object('name', new.name, 'old_name', old.name, 'type', new.type, 'auto_accept', new.auto_accept, 'approved', new.approved, 'old_approved', old.approved));
    end if;
  else perform audit(old.id, 'club_deleted', null, jsonb_build_object('name', old.name));
  end if;
  return null;
end; $$;
drop trigger if exists audit_orgs on orgs;
create trigger audit_orgs after insert or update or delete on orgs for each row execute function audit_orgs();

-- Plan edits happen on every save, so log one line per coach and player every 10 minutes
create or replace function audit_plans() returns trigger language plpgsql security definer set search_path = public as $$
declare o uuid := coalesce(new.org_id, old.org_id); t uuid := coalesce(new.player_id, old.player_id);
begin
  if tg_op = 'DELETE' then perform audit(o, 'plan_removed', t, '{}'::jsonb); return null; end if;
  if not exists (select 1 from audit_log where org_id = o and target = t and action = 'plan_changed' and actor is not distinct from auth.uid() and at > now() - interval '10 minutes') then
    perform audit(o, 'plan_changed', t, '{}'::jsonb);
  end if;
  return null;
end; $$;
drop trigger if exists audit_plans on player_plans;
create trigger audit_plans after insert or update or delete on player_plans for each row execute function audit_plans();

create or replace function audit_club_plans() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if not exists (select 1 from audit_log where org_id = new.org_id and target is null and action = 'club_plans_changed' and actor is not distinct from auth.uid() and at > now() - interval '10 minutes') then
    perform audit(new.org_id, 'club_plans_changed', null, '{}'::jsonb);
  end if;
  return null;
end; $$;
drop trigger if exists audit_club_plans on org_state;
create trigger audit_club_plans after update on org_state for each row execute function audit_club_plans();

-- Parent decisions and reports: StandPoint staff only (no club id)
create or replace function audit_parent_links() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if tg_op = 'DELETE' then perform audit(null, 'parent_unlinked', old.player_id, jsonb_build_object('parent', old.parent_id)); return null; end if;
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    perform audit(null, case when new.status = 'approved' then 'parent_approved' else 'parent_paused' end, new.player_id, jsonb_build_object('parent', new.parent_id, 'consent_version', new.consent_version));
  end if;
  return null;
end; $$;
drop trigger if exists audit_parent_links on parent_links;
create trigger audit_parent_links after insert or update or delete on parent_links for each row execute function audit_parent_links();

-- A coach or admin reads the last 100 events in his club, newest first, with names
create or replace function club_history(o uuid, before_id bigint default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_coach(o) then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('id', a.id, 'at', a.at, 'action', a.action, 'detail', a.detail,
      'actor', coalesce(pa.display_name, case when a.actor is null then 'StandPoint' else 'Someone' end),
      'target', pt.display_name) order by a.id desc)
    from (select * from audit_log where org_id = o and (before_id is null or id < before_id) order by id desc limit 100) a
    left join profiles pa on pa.id = a.actor
    left join profiles pt on pt.id = a.target), '[]'::jsonb) end;
$$;

-- ============ 7. Reports ============
create table if not exists reports (
  id uuid primary key default gen_random_uuid(),
  reporter_id uuid references auth.users(id) on delete set null,
  org_id uuid references orgs(id) on delete set null,
  org_name text,
  about_user_id uuid references auth.users(id) on delete set null,
  about_name text,
  reason text not null check (reason in ('messages', 'unsafe_training', 'uncomfortable', 'privacy', 'other')),
  details text not null default '' check (char_length(details) <= 4000),
  status text not null default 'new' check (status in ('new', 'reviewing', 'closed')),
  resolution text,
  handled_by uuid references auth.users(id) on delete set null,
  handled_at timestamptz,
  notified_at timestamptz,
  created_at timestamptz not null default now()
);
alter table reports enable row level security;
drop policy if exists "I see my own reports" on reports;
create policy "I see my own reports" on reports for select using (reporter_id = auth.uid());
revoke insert, update, delete on reports from anon, authenticated;

create or replace function file_report(o uuid, about uuid, why text, details text default '') returns uuid
language plpgsql security definer set search_path = public as $$
declare rid uuid; oname text; aname text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if why not in ('messages', 'unsafe_training', 'uncomfortable', 'privacy', 'other') then raise exception 'Pick a reason'; end if;
  if (select count(*) from reports where reporter_id = auth.uid() and created_at > now() - interval '1 day') >= 10 then
    raise exception 'You''ve sent a lot of reports today. Email StandPoint directly if this is urgent.';
  end if;
  if o is not null then
    -- The club has to be one I'm in (or my child is in)
    if not exists (select 1 from memberships m where m.org_id = o and (m.user_id = auth.uid() or is_parent_of(m.user_id))) then raise exception 'You can only report about your own club'; end if;
    select name into oname from orgs where id = o;
  end if;
  if about is not null then
    if o is null or not exists (select 1 from memberships where org_id = o and user_id = about and role in ('admin', 'coach')) then raise exception 'That person isn''t a coach in this club'; end if;
    select display_name into aname from profiles where id = about;
  end if;
  insert into reports (reporter_id, org_id, org_name, about_user_id, about_name, reason, details)
    values (auth.uid(), o, oname, about, aname, why, left(coalesce(details, ''), 4000)) returning id into rid;
  perform audit(null, 'report_filed', about, jsonb_build_object('report', rid, 'org', o));
  return rid;
end; $$;

-- ============ 8. What the app asks on start ============
create or replace function my_status() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'birthdate_set', has_birthdate(auth.uid()),
    'adult', is_adult(auth.uid()),
    'cleared', player_cleared(auth.uid()),
    'parents', (select count(*) from parent_links where player_id = auth.uid()),
    'parents_paused', (select count(*) from parent_links where player_id = auth.uid() and status = 'paused'),
    'is_parent', coalesce((select is_parent from profiles where id = auth.uid()), false) or exists (select 1 from parent_links where parent_id = auth.uid()),
    'sp_admin', is_sp_admin(),
    'blocked', exists (select 1 from sp_blocked where user_id = auth.uid()),
    'unapproved_clubs', coalesce((select jsonb_agg(o.id) from memberships m join orgs o on o.id = m.org_id where m.user_id = auth.uid() and not o.approved), '[]'::jsonb));
$$;

-- For accounts made before birthdates: set it once. Only StandPoint can change it after that.
create or replace function set_birthdate(d date) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if d is null then raise exception 'Add your birthdate'; end if;
  if has_birthdate(auth.uid()) then raise exception 'Your birthdate is already set. Email StandPoint to change it.'; end if;
  if d > (current_date - interval '13 years')::date then raise exception 'StandPoint is for ages 13 and up.'; end if;
  if d < (current_date - interval '100 years')::date then raise exception 'Check the year.'; end if;
  insert into person_facts (user_id, birthdate) values (auth.uid(), d)
    on conflict (user_id) do update set birthdate = excluded.birthdate, updated_at = now();
  update profiles set age_ok = true where id = auth.uid();
  return my_status();
end; $$;

-- ============ 9. Clubs: adults only, approved before players join, blocked people can't join ============
create or replace function create_org(org_name text, org_type text default 'Training facility')
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if exists (select 1 from sp_blocked where user_id = auth.uid()) then raise exception 'This account can''t start a club. Email StandPoint.'; end if;
  if not has_birthdate(auth.uid()) then raise exception 'Add your birthdate first.'; end if;
  if not is_adult(auth.uid()) then raise exception 'Clubs are started by adults 18 and older.'; end if;
  if char_length(trim(coalesce(org_name, ''))) = 0 then raise exception 'Give your club a name.'; end if;
  insert into orgs (name, type, join_code, created_by)
    values (left(trim(org_name), 80), left(coalesce(org_type, 'Training facility'), 40), make_join_code(), auth.uid())
    returning id into new_id;
  insert into memberships (org_id, user_id, role, status) values (new_id, auth.uid(), 'admin', 'active');
  insert into org_state (org_id) values (new_id);
  insert into org_private (org_id) values (new_id);
  return new_id;
end; $$;

create or replace function join_org(code text, as_role text default 'player', team text default null)
returns text language plpgsql security definer set search_path = public as $$
declare o orgs%rowtype; st text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if as_role not in ('player', 'coach') then raise exception 'Unknown role'; end if;
  if exists (select 1 from sp_blocked where user_id = auth.uid()) then raise exception 'This account can''t join clubs. Email StandPoint.'; end if;
  if not has_birthdate(auth.uid()) then raise exception 'Add your birthdate first.'; end if;
  if as_role = 'coach' and not is_adult(auth.uid()) then raise exception 'Coaches have to be 18 or older.'; end if;
  perform check_join_tries();
  select * into o from orgs where join_code = clean_code(code);
  if not found then insert into join_attempts (user_id) values (auth.uid()); return 'bad_code'; end if;
  if exists (select 1 from memberships where org_id = o.id and user_id = auth.uid()) then return 'already'; end if;
  if as_role = 'player' and not o.approved then return 'not_approved'; end if;
  st := case when o.auto_accept and as_role = 'player' then 'active' else 'pending' end;
  insert into memberships (org_id, user_id, role, status, team_id) values (o.id, auth.uid(), as_role, st, left(team, 64));
  return st;
end; $$;

-- ============ 10. Parent actions ============
create or replace function my_family_code() returns text
language plpgsql security definer set search_path = public as $$
declare c text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if is_adult(auth.uid()) then raise exception 'Only players under 18 need a parent code.'; end if;
  select code into c from family_codes where player_id = auth.uid();
  if c is null then
    c := make_join_code();
    while exists (select 1 from family_codes where code = c) loop c := make_join_code(); end loop;
    insert into family_codes (player_id, code) values (auth.uid(), c);
  end if;
  return c;
end; $$;

create or replace function link_child(code text, agree boolean, consent_version text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pid uuid; nm text;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  if not has_birthdate(auth.uid()) or not is_adult(auth.uid()) then raise exception 'Parent accounts are for adults 18 and older.'; end if;
  if not coalesce(agree, false) then raise exception 'Read and check the consent box first.'; end if;
  perform check_join_tries();
  select player_id into pid from family_codes where family_codes.code = clean_code(link_child.code);
  if pid is null then insert into join_attempts (user_id) values (auth.uid()); return jsonb_build_object('status', 'bad_code'); end if;
  if pid = auth.uid() then raise exception 'Use your player''s code, not your own.'; end if;
  insert into parent_links (player_id, parent_id, status, consent_version, approved_at)
    values (pid, auth.uid(), 'approved', left(consent_version, 40), now())
    on conflict (player_id, parent_id) do update set status = 'approved', consent_version = excluded.consent_version, approved_at = now(), paused_at = null;
  update profiles set is_parent = true where id = auth.uid();
  delete from family_codes where player_id = pid;   -- one-time code
  select display_name into nm from profiles where id = pid;
  return jsonb_build_object('status', 'linked', 'player_id', pid, 'name', nm);
end; $$;

create or replace function set_consent(p uuid, approve boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_parent_of(p) then raise exception 'You''re not linked to this player.'; end if;
  update parent_links set status = case when approve then 'approved' else 'paused' end,
    approved_at = case when approve then now() else approved_at end,
    paused_at = case when approve then null else now() end
  where player_id = p and parent_id = auth.uid();
end; $$;

create or replace function parent_remove_club(p uuid, o uuid) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_parent_of(p) then raise exception 'You''re not linked to this player.'; end if;
  delete from memberships where user_id = p and org_id = o and role = 'player';
end; $$;

-- What a parent sees: who can see his player's data, and a few counts. Not the logs or notes themselves.
create or replace function my_children() returns jsonb
language sql stable security definer set search_path = public, storage as $$
  select coalesce(jsonb_agg(jsonb_build_object(
    'player_id', l.player_id, 'name', pp.display_name, 'status', l.status, 'approved_at', l.approved_at,
    'adult', is_adult(l.player_id), 'last_active', ps.updated_at,
    'videos', (select count(*) from storage.objects so where so.bucket_id = 'videos' and so.name like l.player_id::text || '/%'),
    'clubs', coalesce((select jsonb_agg(jsonb_build_object('org_id', o.id, 'name', o.name, 'status', m.status, 'approved', o.approved,
        'coaches', coalesce((select jsonb_agg(jsonb_build_object('id', cp.id, 'name', cp.display_name) order by cp.display_name) from memberships cm join profiles cp on cp.id = cm.user_id
                             where cm.org_id = o.id and cm.status = 'active' and cm.role in ('admin', 'coach')), '[]'::jsonb)))
      from memberships m join orgs o on o.id = m.org_id where m.user_id = l.player_id and m.role = 'player'), '[]'::jsonb)
  ) order by pp.display_name), '[]'::jsonb)
  from parent_links l join profiles pp on pp.id = l.player_id left join player_state ps on ps.user_id = l.player_id
  where l.parent_id = auth.uid();
$$;

-- ============ 11. Deleting an account can't wipe out a club other people are in ============
-- Clubs where I'm the only admin and other people are still in it
create or replace function delete_check() returns jsonb
language sql stable security definer set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('org_id', o.id, 'name', o.name,
      'members', (select count(*) from memberships x where x.org_id = o.id and x.user_id <> auth.uid()))), '[]'::jsonb)
  from orgs o join memberships me on me.org_id = o.id and me.user_id = auth.uid() and me.role = 'admin' and me.status = 'active'
  where not exists (select 1 from memberships a where a.org_id = o.id and a.role = 'admin' and a.status = 'active' and a.user_id <> auth.uid())
    and exists (select 1 from memberships x where x.org_id = o.id and x.user_id <> auth.uid());
$$;

create or replace function delete_me()
returns void language plpgsql security definer set search_path = public as $$
declare blocked jsonb;
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  blocked := delete_check();
  if jsonb_array_length(blocked) > 0 then
    raise exception 'Make another coach an admin of % first, or remove its members. Then you can delete your account.',
      (select string_agg(x->>'name', ', ') from jsonb_array_elements(blocked) x);
  end if;
  -- Clubs where I'm the only person left go with me
  delete from orgs o using memberships me
    where me.org_id = o.id and me.user_id = auth.uid() and me.role = 'admin'
      and not exists (select 1 from memberships x where x.org_id = o.id and x.user_id <> auth.uid());
  delete from auth.users where id = auth.uid();
end; $$;

-- ============ 12. StandPoint staff tools (the app's Admin tab) ============
create or replace function sp_orgs() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_sp_admin() then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('id', o.id, 'name', o.name, 'type', o.type, 'approved', o.approved, 'created_at', o.created_at,
      'creator', coalesce(p.display_name, ''), 'creator_email', u.email,
      'coaches', (select count(*) from memberships m where m.org_id = o.id and m.role in ('admin', 'coach') and m.status = 'active'),
      'players', (select count(*) from memberships m where m.org_id = o.id and m.role = 'player' and m.status = 'active'))
      order by o.approved, o.created_at desc)
    from orgs o left join profiles p on p.id = o.created_by left join auth.users u on u.id = o.created_by), '[]'::jsonb) end;
$$;

create or replace function sp_approve_org(o uuid, yes boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_sp_admin() then raise exception 'StandPoint staff only'; end if;
  update orgs set approved = yes, approved_at = case when yes then now() else null end where id = o;
end; $$;

create or replace function sp_invites() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_sp_admin() then '{}'::jsonb else jsonb_build_object(
    'invite_only', (select invite_only from app_settings where id = 1),
    'invites', coalesce((select jsonb_agg(jsonb_build_object('email', i.email, 'note', i.note, 'added_at', i.added_at,
        'joined', exists (select 1 from auth.users u where lower(u.email) = i.email)) order by i.added_at desc) from signup_invites i), '[]'::jsonb)) end;
$$;

create or replace function sp_invite(e text, n text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_sp_admin() then raise exception 'StandPoint staff only'; end if;
  if lower(trim(coalesce(e, ''))) !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then raise exception 'That doesn''t look like an email address.'; end if;
  insert into signup_invites (email, note, added_by) values (lower(trim(e)), left(n, 200), auth.uid())
    on conflict (email) do update set note = coalesce(excluded.note, signup_invites.note);
end; $$;

create or replace function sp_uninvite(e text) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_sp_admin() then raise exception 'StandPoint staff only'; end if;
  delete from signup_invites where email = lower(trim(e));
end; $$;

create or replace function sp_set_invite_only(yes boolean) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_sp_admin() then raise exception 'StandPoint staff only'; end if;
  update app_settings set invite_only = yes where id = 1;
end; $$;

create or replace function sp_reports() returns jsonb
language sql stable security definer set search_path = public as $$
  select case when not is_sp_admin() then '[]'::jsonb else coalesce((
    select jsonb_agg(jsonb_build_object('id', r.id, 'created_at', r.created_at, 'reason', r.reason, 'details', r.details, 'status', r.status,
      'resolution', r.resolution, 'org_id', r.org_id, 'org_name', r.org_name, 'about_user_id', r.about_user_id, 'about_name', r.about_name,
      'reporter', coalesce(rp.display_name, ''), 'reporter_email', ru.email,
      'about_blocked', exists (select 1 from sp_blocked b where b.user_id = r.about_user_id))
      order by (r.status = 'closed'), r.created_at desc)
    from reports r left join profiles rp on rp.id = r.reporter_id left join auth.users ru on ru.id = r.reporter_id), '[]'::jsonb) end;
$$;

create or replace function sp_set_report(rid uuid, st text, note text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_sp_admin() then raise exception 'StandPoint staff only'; end if;
  if st not in ('new', 'reviewing', 'closed') then raise exception 'Unknown status'; end if;
  update reports set status = st, resolution = coalesce(left(note, 2000), resolution), handled_by = auth.uid(), handled_at = now() where id = rid;
end; $$;

-- Suspend a coach everywhere (his coach and admin spots), and stop him starting or joining clubs. Or undo it.
create or replace function sp_suspend(u uuid, yes boolean, why text default null) returns void
language plpgsql security definer set search_path = public as $$
begin
  if not is_sp_admin() then raise exception 'StandPoint staff only'; end if;
  if yes then
    update memberships set status = 'suspended' where user_id = u and role in ('admin', 'coach') and status <> 'suspended';
    insert into sp_blocked (user_id, reason) values (u, left(why, 500)) on conflict (user_id) do update set reason = excluded.reason, at = now();
  else
    update memberships set status = 'active' where user_id = u and status = 'suspended';
    delete from sp_blocked where user_id = u;
  end if;
end; $$;

-- ============ 13. Who can run what ============
revoke execute on function is_sp_admin(), is_adult(uuid), has_birthdate(uuid), is_parent_of(uuid), player_cleared(uuid), audit(uuid, text, uuid, jsonb),
  club_history(uuid, bigint), file_report(uuid, uuid, text, text), my_status(), set_birthdate(date), create_org(text, text), join_org(text, text, text),
  my_family_code(), link_child(text, boolean, text), set_consent(uuid, boolean), parent_remove_club(uuid, uuid), my_children(),
  delete_check(), delete_me(), sp_orgs(), sp_approve_org(uuid, boolean), sp_invites(), sp_invite(text, text), sp_uninvite(text),
  sp_set_invite_only(boolean), sp_reports(), sp_set_report(uuid, text, text), sp_suspend(uuid, boolean, text) from anon, public;
grant execute on function is_sp_admin(), is_adult(uuid), has_birthdate(uuid), is_parent_of(uuid), player_cleared(uuid),
  club_history(uuid, bigint), file_report(uuid, uuid, text, text), my_status(), set_birthdate(date), create_org(text, text), join_org(text, text, text),
  my_family_code(), link_child(text, boolean, text), set_consent(uuid, boolean), parent_remove_club(uuid, uuid), my_children(),
  delete_check(), delete_me(), sp_orgs(), sp_approve_org(uuid, boolean), sp_invites(), sp_invite(text, text), sp_uninvite(text),
  sp_set_invite_only(boolean), sp_reports(), sp_set_report(uuid, text, text), sp_suspend(uuid, boolean, text) to authenticated;

-- ============ LAST STEP: make yourself StandPoint staff ============
-- Delete the two dashes at the start of the next line, put your sign-in email between the quotes, and run just that line.
-- Never save your email into this file in GitHub.
-- insert into sp_admins (user_id) select id from auth.users where lower(email) = lower('YOUR-EMAIL') on conflict do nothing;

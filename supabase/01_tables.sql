-- StandPoint version 1 · Step 2: tables
-- Paste into Supabase → SQL Editor → New query → Run. Run it once.

-- Who each person is (one row per sign-in)
create table profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null default '',
  is_coach boolean not null default false,
  age_ok boolean not null default false,          -- checked "I'm 13 or older" at sign-up
  created_at timestamptz not null default now()
);

-- A club, training facility or high school program
create table orgs (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  type text not null default 'Training facility',
  join_code text unique not null,
  auto_accept boolean not null default false,
  created_by uuid default auth.uid() references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- Who belongs to which organization, and as what
create table memberships (
  org_id uuid not null references orgs(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  role text not null check (role in ('admin', 'coach', 'player')),
  status text not null default 'pending' check (status in ('pending', 'active', 'declined')),
  team_id text,
  created_at timestamptz not null default now(),
  primary key (org_id, user_id)
);

-- The club's shared data every member can read: teams, club and team plans, routines
create table org_state (
  org_id uuid primary key references orgs(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null
);

-- What only coaches see: coach notes, the change log
create table org_private (
  org_id uuid primary key references orgs(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

-- One player's own plan inside one club: his plan, focus note, nudges, next lesson
create table player_plans (
  org_id uuid not null references orgs(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now(),
  updated_by uuid references auth.users(id) on delete set null,
  primary key (org_id, player_id)
);

-- Each player's data his coaches can read: profile, numbers, training logs, schools list
create table player_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

-- What only the player sees: private school notes, Ask StandPoint chats
create table player_private (
  user_id uuid primary key references auth.users(id) on delete cascade,
  data jsonb not null default '{}',
  updated_at timestamptz not null default now()
);

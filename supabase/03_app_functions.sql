-- StandPoint version 1 · Step 3b: two more functions the app uses
-- Paste into Supabase → SQL Editor → + → Create a new snippet → Run, after 02_security.sql.

-- The clubs I belong to or asked to join, with the club's name (works while my request is still pending)
create or replace function my_clubs()
returns table (org_id uuid, name text, type text, role text, status text, team_id text)
language sql stable security definer set search_path = public as $$
  select o.id, o.name, o.type, m.role, m.status, m.team_id
  from memberships m join orgs o on o.id = m.org_id
  where m.user_id = auth.uid();
$$;

-- Delete my account and everything tied to it. A club I created goes too, unless another admin runs it.
create or replace function delete_me()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Sign in first'; end if;
  delete from orgs o
    where o.created_by = auth.uid()
      and not exists (select 1 from memberships m
        where m.org_id = o.id and m.role = 'admin' and m.status = 'active' and m.user_id <> auth.uid());
  delete from auth.users where id = auth.uid();
end; $$;

revoke execute on function my_clubs(), delete_me() from anon, public;
grant execute on function my_clubs(), delete_me() to authenticated;

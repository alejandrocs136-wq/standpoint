-- StandPoint · Step 5: video beta (Nov 7, 2026)
-- Paste into Supabase → SQL Editor → New query → Run, after 01–04. Safe to run more than once.
-- Makes a private "videos" storage bucket. Each player's videos live in a folder named after his account.
-- Only he can add or delete them; he and the coaches of his club can watch them. Nobody else can, and there are no public links.

-- 1. The bucket: private, videos only, 50 MB a file (the most Supabase's free plan allows; raise it on Pro if needed)
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('videos', 'videos', false, 52428800, array['video/*'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;

-- 2. How many videos a player has (the app caps it at 20; this stops a script from going around the app)
create or replace function public.my_video_count() returns int
language sql stable security definer set search_path = public, storage as $$
  select count(*)::int from storage.objects where bucket_id = 'videos' and name like auth.uid()::text || '/%';
$$;
revoke execute on function public.my_video_count() from anon, public;
grant execute on function public.my_video_count() to authenticated;

-- Is this folder name a player I coach? (checks the name looks like an account id before using it as one)
create or replace function public.coaches_folder(folder text) returns boolean
language sql stable security definer set search_path = public as $$
  select case when folder ~ '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' then coaches_player(folder::uuid) else false end;
$$;
revoke execute on function public.coaches_folder(text) from anon, public;
grant execute on function public.coaches_folder(text) to authenticated;

-- 3. The rules
drop policy if exists "players add their own videos" on storage.objects;
create policy "players add their own videos" on storage.objects for insert to authenticated
  with check (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text and public.my_video_count() < 20);

drop policy if exists "player and his coaches watch" on storage.objects;
create policy "player and his coaches watch" on storage.objects for select to authenticated
  using (bucket_id = 'videos' and ((storage.foldername(name))[1] = auth.uid()::text or public.coaches_folder((storage.foldername(name))[1])));

drop policy if exists "players delete their own videos" on storage.objects;
create policy "players delete their own videos" on storage.objects for delete to authenticated
  using (bucket_id = 'videos' and (storage.foldername(name))[1] = auth.uid()::text);
-- No update rule: a video can't be swapped out after it's added. Delete it and add a new one.

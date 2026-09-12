insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'patient-avatars',
  'patient-avatars',
  true,
  5242880,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = excluded.public,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Patients can upload own avatar" on storage.objects;
create policy "Patients can upload own avatar"
on storage.objects for insert to authenticated
with check (
  bucket_id = 'patient-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Patients can update own avatar" on storage.objects;
create policy "Patients can update own avatar"
on storage.objects for update to authenticated
using (
  bucket_id = 'patient-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
)
with check (
  bucket_id = 'patient-avatars'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "Patient avatars are publicly readable" on storage.objects;
create policy "Patient avatars are publicly readable"
on storage.objects for select to public
using (bucket_id = 'patient-avatars');

drop policy if exists "Doctors can delete own introduction media"
on storage.objects;

create policy "Doctors can delete own introduction media"
on storage.objects
for delete
to authenticated
using (
  bucket_id = 'doctor-intro-videos'
  and (storage.foldername(name))[1] = auth.uid()::text
);

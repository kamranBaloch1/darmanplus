-- begin;

-- -- Doctors listed here are hidden from the public catalogue and are returned
-- -- only to their explicitly allowed patient accounts.
-- create table if not exists public.doctor_catalogue_audience (
--   doctor_id uuid not null references public.users(uid) on delete cascade,
--   patient_id uuid not null references public.users(uid) on delete cascade,
--   created_at timestamptz not null default now(),
--   primary key (doctor_id, patient_id),
--   check (doctor_id <> patient_id)
-- );

-- create index if not exists doctor_catalogue_audience_patient_id_idx
--   on public.doctor_catalogue_audience(patient_id);

-- alter table public.doctor_catalogue_audience enable row level security;

-- -- The catalogue Edge Function reads this table with the service role. Mobile
-- -- clients must not be able to discover or modify private audience mappings.
-- revoke all on table public.doctor_catalogue_audience from anon, authenticated;

-- insert into public.doctor_catalogue_audience (doctor_id, patient_id)
-- values
--   (
--     'd146b500-50bf-4b17-bb18-70a70c53a0cf',
--     '28affb87-7a1e-4264-ba44-8d1e51e12d10'
--   ),
--   (
--     'd146b500-50bf-4b17-bb18-70a70c53a0cf',
--     '7cfe65c3-e1be-4b58-820d-61182ae1d388'
--   )
-- on conflict (doctor_id, patient_id) do nothing;

-- commit;

-- insert into public.doctor_catalogue_audience (doctor_id, patient_id)
-- values (
--   'DOCTOR_UUID',
--   'PATIENT_UUID'
-- )
-- on conflict (doctor_id, patient_id) do nothing;
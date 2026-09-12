begin;

alter table public.users
  add column if not exists is_admin_suspended boolean not null default false,
  add column if not exists is_catalogue_hidden boolean not null default false;

create table if not exists public.admin_doctor_notes (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.users(uid) on delete cascade,
  author_email text not null,
  body text not null check (char_length(btrim(body)) between 1 and 2000),
  created_at timestamptz not null default now()
);

create index if not exists admin_doctor_notes_doctor_id_created_at_idx on public.admin_doctor_notes(doctor_id, created_at desc);
alter table public.admin_doctor_notes enable row level security;
revoke all on public.admin_doctor_notes from anon, authenticated;

create table if not exists public.admin_doctor_document_reviews (
  doctor_id uuid not null references public.users(uid) on delete cascade,
  document_path text not null,
  status text not null check (status in ('approved','rejected','pending')) default 'pending',
  reason text,
  reviewed_by text,
  reviewed_at timestamptz,
  primary key (doctor_id, document_path)
);
alter table public.admin_doctor_document_reviews enable row level security;
revoke all on public.admin_doctor_document_reviews from anon, authenticated;

commit;

begin;

create table if not exists public.admin_announcements (
  id uuid primary key default gen_random_uuid(),
  sent_by text not null,
  audience text not null check (audience in ('all_doctors', 'all_patients', 'specific_doctor', 'specific_patient')),
  recipient_id uuid references public.users(uid) on delete set null,
  title text not null,
  message text not null,
  recipient_count integer not null default 0,
  delivered_count integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.admin_announcements enable row level security;
revoke all on public.admin_announcements from anon, authenticated;

commit;

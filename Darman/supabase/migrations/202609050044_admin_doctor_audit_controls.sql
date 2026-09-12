begin;

create table if not exists public.admin_doctor_audit_log (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.users(uid) on delete cascade,
  admin_email text not null,
  action text not null,
  detail jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists admin_doctor_audit_log_doctor_created_idx on public.admin_doctor_audit_log(doctor_id, created_at desc);
alter table public.admin_doctor_audit_log enable row level security;
revoke all on public.admin_doctor_audit_log from anon, authenticated;

commit;

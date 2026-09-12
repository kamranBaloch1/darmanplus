create table if not exists public.consultation_call_invites (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null references public.bookings(id) on delete cascade,
  caller_id uuid not null references public.users(uid) on delete cascade,
  callee_id uuid not null references public.users(uid) on delete cascade,
  caller_name text not null,
  callee_name text not null,
  caller_is_doctor boolean not null,
  callee_is_doctor boolean not null,
  status text not null default 'ringing'
    check (status in ('ringing', 'accepted', 'declined', 'cancelled', 'expired')),
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default (now() + interval '1 hour'),
  responded_at timestamptz,
  updated_at timestamptz not null default now(),
  check (caller_id <> callee_id)
);

create unique index if not exists one_ringing_call_per_booking
  on public.consultation_call_invites(booking_id)
  where status = 'ringing';

create index if not exists call_invites_callee_created_idx
  on public.consultation_call_invites(callee_id, created_at desc);

alter table public.consultation_call_invites enable row level security;
alter table public.consultation_call_invites replica identity full;
grant select on public.consultation_call_invites to authenticated;

drop policy if exists "Participants can view their call invitations"
  on public.consultation_call_invites;
create policy "Participants can view their call invitations"
  on public.consultation_call_invites for select
  using (auth.uid() in (caller_id, callee_id));

create or replace function public.start_consultation_video_call(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  b public.bookings%rowtype;
  active_invite public.consultation_call_invites%rowtype;
  caller_name_value text;
  callee_name_value text;
  callee_id_value uuid;
  invite_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b from public.bookings where id = p_booking_id;
  if not found or auth.uid() not in (b.patient_id, b.doctor_id) then
    raise exception 'Access denied';
  end if;
  if b.status <> 'inProgress' then
    raise exception 'The consultation must be started before calling';
  end if;

  update public.consultation_call_invites
  set status = 'expired', updated_at = now()
  where booking_id = p_booking_id
    and status = 'ringing'
    and expires_at <= now();

  select * into active_invite
  from public.consultation_call_invites
  where booking_id = p_booking_id and status = 'ringing'
  limit 1;

  if found then
    if active_invite.caller_id = auth.uid() then
      return active_invite.id;
    end if;
    raise exception 'The other participant is already calling you';
  end if;

  callee_id_value := case
    when auth.uid() = b.doctor_id then b.patient_id
    else b.doctor_id
  end;

  select coalesce(
    nullif(raw_user_meta_data ->> 'full_name', ''),
    nullif(raw_user_meta_data ->> 'name', ''),
    nullif(email, ''),
    'Caller'
  ) into caller_name_value
  from auth.users where id = auth.uid();

  select coalesce(
    nullif(raw_user_meta_data ->> 'full_name', ''),
    nullif(raw_user_meta_data ->> 'name', ''),
    nullif(email, ''),
    'Participant'
  ) into callee_name_value
  from auth.users where id = callee_id_value;

  insert into public.consultation_call_invites (
    booking_id,
    caller_id,
    callee_id,
    caller_name,
    callee_name,
    caller_is_doctor,
    callee_is_doctor
  ) values (
    p_booking_id,
    auth.uid(),
    callee_id_value,
    coalesce(caller_name_value, 'Caller'),
    coalesce(callee_name_value, 'Participant'),
    auth.uid() = b.doctor_id,
    callee_id_value = b.doctor_id
  ) returning id into invite_id;

  return invite_id;
exception
  when unique_violation then
    raise exception 'A call is already ringing for this consultation';
end;
$$;

create or replace function public.respond_consultation_video_call(
  p_invite_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  invite public.consultation_call_invites%rowtype;
begin
  select * into invite
  from public.consultation_call_invites
  where id = p_invite_id
  for update;

  if not found or auth.uid() is null or auth.uid() <> invite.callee_id then
    raise exception 'Access denied';
  end if;
  if invite.status <> 'ringing' then
    raise exception 'This call request is no longer active';
  end if;
  if invite.expires_at <= now() then
    update public.consultation_call_invites
    set status = 'expired', updated_at = now()
    where id = p_invite_id;
    return;
  end if;

  update public.consultation_call_invites
  set status = case when p_accept then 'accepted' else 'declined' end,
      responded_at = now(),
      updated_at = now()
  where id = p_invite_id;
end;
$$;

create or replace function public.cancel_consultation_video_call(p_invite_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.consultation_call_invites
  set status = 'cancelled', responded_at = now(), updated_at = now()
  where id = p_invite_id
    and caller_id = auth.uid()
    and status = 'ringing';

  if not found then
    raise exception 'This call request cannot be cancelled';
  end if;
end;
$$;

revoke all on function public.start_consultation_video_call(uuid) from public;
revoke all on function public.respond_consultation_video_call(uuid, boolean) from public;
revoke all on function public.cancel_consultation_video_call(uuid) from public;
grant execute on function public.start_consultation_video_call(uuid) to authenticated;
grant execute on function public.respond_consultation_video_call(uuid, boolean) to authenticated;
grant execute on function public.cancel_consultation_video_call(uuid) to authenticated;

do $$
begin
  alter publication supabase_realtime add table public.consultation_call_invites;
exception
  when duplicate_object then null;
end $$;

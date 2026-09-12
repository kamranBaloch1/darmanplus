begin;

-- Accepted invitations used to remain accepted forever. Give completed calls a
-- terminal state so they cannot make either participant appear permanently busy.
alter table public.consultation_call_invites
  drop constraint if exists consultation_call_invites_status_check;

alter table public.consultation_call_invites
  add constraint consultation_call_invites_status_check
  check (status in (
    'ringing',
    'accepted',
    'declined',
    'cancelled',
    'expired',
    'ended'
  ));

update public.consultation_call_invites i
set status = 'ended',
    updated_at = now()
from public.bookings b
where i.booking_id = b.id
  and i.status = 'accepted'
  and (
    b.call_ended_at is not null
    or coalesce(i.responded_at, i.created_at) < now() - interval '2 hours'
  );

update public.consultation_call_invites
set status = 'expired',
    updated_at = now()
where status = 'ringing'
  and expires_at <= now();

create index if not exists call_invites_active_participants_idx
  on public.consultation_call_invites(caller_id, callee_id, updated_at desc)
  where status in ('ringing', 'accepted');

create or replace function public.start_consultation_video_call(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  b public.bookings%rowtype;
  existing_invite public.consultation_call_invites%rowtype;
  conflicting_invite public.consultation_call_invites%rowtype;
  caller_name_value text;
  callee_name_value text;
  callee_id_value uuid;
  invite_id uuid;
  first_lock bigint;
  second_lock bigint;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id;

  if not found or auth.uid() not in (b.patient_id, b.doctor_id) then
    raise exception 'Access denied';
  end if;
  if b.status <> 'inProgress' then
    raise exception 'The consultation must be started before calling';
  end if;

  callee_id_value := case
    when auth.uid() = b.doctor_id then b.patient_id
    else b.doctor_id
  end;

  -- Lock both participants in a stable order. Two devices starting calls at the
  -- same instant therefore cannot both pass the busy check.
  first_lock := hashtextextended(least(auth.uid()::text, callee_id_value::text), 0);
  second_lock := hashtextextended(greatest(auth.uid()::text, callee_id_value::text), 0);
  perform pg_advisory_xact_lock(first_lock);
  perform pg_advisory_xact_lock(second_lock);

  update public.consultation_call_invites
  set status = 'expired', updated_at = now()
  where status = 'ringing'
    and expires_at <= now()
    and (
      auth.uid() in (caller_id, callee_id)
      or callee_id_value in (caller_id, callee_id)
    );

  -- Reopening an already accepted call from another device must reuse it.
  select * into existing_invite
  from public.consultation_call_invites
  where booking_id = p_booking_id
    and status in ('ringing', 'accepted')
  order by created_at desc
  limit 1;

  if found then
    if existing_invite.status = 'accepted'
      or existing_invite.caller_id = auth.uid() then
      return existing_invite.id;
    end if;
    raise exception 'An incoming call from this participant is already waiting';
  end if;

  select * into conflicting_invite
  from public.consultation_call_invites
  where status in ('ringing', 'accepted')
    and (
      auth.uid() in (caller_id, callee_id)
      or callee_id_value in (caller_id, callee_id)
    )
  order by created_at desc
  limit 1;

  if found then
    if auth.uid() in (
      conflicting_invite.caller_id,
      conflicting_invite.callee_id
    ) then
      raise exception 'You are currently on another call';
    end if;
    raise exception 'This user is currently on another call';
  end if;

  select coalesce(
    nullif(raw_user_meta_data ->> 'full_name', ''),
    nullif(raw_user_meta_data ->> 'name', ''),
    nullif(email, ''),
    'Caller'
  ) into caller_name_value
  from auth.users
  where id = auth.uid();

  select coalesce(
    nullif(raw_user_meta_data ->> 'full_name', ''),
    nullif(raw_user_meta_data ->> 'name', ''),
    nullif(email, ''),
    'Participant'
  ) into callee_name_value
  from auth.users
  where id = callee_id_value;

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
    raise exception 'A call is already active for this consultation';
end;
$$;

create or replace function public.end_active_video_call(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
begin
  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if not found or auth.uid() not in (b.patient_id, b.doctor_id) then
    raise exception 'Access denied';
  end if;
  if b.status <> 'inProgress' then
    raise exception 'The consultation is not in progress';
  end if;

  if b.call_ended_at is null then
    update public.bookings
    set call_ended_at = now(),
        patient_left_at = case
          when auth.uid() = patient_id then now()
          else patient_left_at
        end,
        doctor_left_at = case
          when auth.uid() = doctor_id then now()
          else doctor_left_at
        end,
        updated_at = now()
    where id = p_booking_id;
  end if;

  update public.consultation_call_invites
  set status = 'ended',
      updated_at = now()
  where booking_id = p_booking_id
    and status = 'accepted';
end;
$$;

revoke all on function public.start_consultation_video_call(uuid) from public;
revoke all on function public.end_active_video_call(uuid) from public;
grant execute on function public.start_consultation_video_call(uuid) to authenticated;
grant execute on function public.end_active_video_call(uuid) to authenticated;

commit;

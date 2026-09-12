begin;

alter table public.bookings
  add column if not exists follow_up_ended_at timestamptz,
  add column if not exists follow_up_ended_by uuid references auth.users(id),
  add column if not exists follow_up_patient_end_seen_at timestamptz,
  add column if not exists follow_up_doctor_end_seen_at timestamptz;

create index if not exists bookings_patient_unseen_follow_up_end_idx
  on public.bookings(patient_id, follow_up_ended_at)
  where follow_up_ended_at is not null
    and follow_up_patient_end_seen_at is null;

create index if not exists bookings_doctor_unseen_follow_up_end_idx
  on public.bookings(doctor_id, follow_up_ended_at)
  where follow_up_ended_at is not null
    and follow_up_doctor_end_seen_at is null;

create or replace function public.claim_due_consultation_follow_up_notifications()
returns table (
  booking_id uuid,
  patient_id uuid,
  doctor_id uuid,
  follow_up_date date,
  patient_notified_at timestamptz,
  doctor_notified_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  local_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  return query
  with due as (
    select b.id
    from public.bookings b
    where b.status = 'completed'
      and b.follow_up_date = local_today
      and b.follow_up_ended_at is null
      and (
        b.follow_up_day_patient_notified_at is null
        or b.follow_up_day_doctor_notified_at is null
      )
      and (
        b.follow_up_day_notification_claimed_at is null
        or b.follow_up_day_notification_claimed_at < now() - interval '15 minutes'
      )
    order by b.follow_up_scheduled_at, b.id
    for update skip locked
    limit 100
  ), claimed as (
    update public.bookings b
    set follow_up_day_notification_claimed_at = now()
    from due
    where b.id = due.id
    returning
      b.id,
      b.patient_id,
      b.doctor_id,
      b.follow_up_date,
      b.follow_up_day_patient_notified_at,
      b.follow_up_day_doctor_notified_at
  )
  select
    claimed.id,
    claimed.patient_id,
    claimed.doctor_id,
    claimed.follow_up_date,
    claimed.follow_up_day_patient_notified_at,
    claimed.follow_up_day_doctor_notified_at
  from claimed;
end;
$$;

revoke all on function public.claim_due_consultation_follow_up_notifications()
  from public;
grant execute on function public.claim_due_consultation_follow_up_notifications()
  to service_role;

create or replace function public.schedule_consultation_follow_up(
  p_booking_id uuid,
  p_follow_up_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;
  if auth.uid() <> b.doctor_id then
    raise exception 'Only the assigned doctor can schedule a follow-up';
  end if;
  if b.status <> 'completed' then
    raise exception 'Complete the consultation before scheduling a follow-up';
  end if;
  if p_follow_up_date <= local_today then
    raise exception 'Choose a future follow-up date';
  end if;
  if p_follow_up_date > local_today + 365 then
    raise exception 'The follow-up date must be within one year';
  end if;

  update public.bookings
  set follow_up_date = p_follow_up_date,
      follow_up_scheduled_at = now(),
      follow_up_patient_seen_at = null,
      follow_up_ended_at = null,
      follow_up_ended_by = null,
      follow_up_patient_end_seen_at = null,
      follow_up_doctor_end_seen_at = null,
      updated_at = now()
  where id = b.id;

  update public.chat_rooms
  set is_active = true,
      updated_at = now()
  where booking_id = b.id;

  return jsonb_build_object(
    'booking_id', b.id,
    'patient_id', b.patient_id,
    'doctor_id', b.doctor_id,
    'follow_up_date', p_follow_up_date,
    'follow_up_scheduled_at', now()
  );
end;
$$;

create or replace function public.end_consultation_follow_up(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  ended_at_value timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;
  if auth.uid() <> b.doctor_id then
    raise exception 'Only the assigned doctor can end the follow-up';
  end if;
  if b.status <> 'completed' or b.follow_up_date is null then
    raise exception 'Follow-up not found';
  end if;
  if b.follow_up_date > local_today then
    raise exception 'The follow-up has not started yet';
  end if;

  if b.follow_up_ended_at is not null then
    return jsonb_build_object(
      'booking_id', b.id,
      'follow_up_ended_at', b.follow_up_ended_at
    );
  end if;

  ended_at_value := now();
  update public.bookings
  set follow_up_ended_at = ended_at_value,
      follow_up_ended_by = auth.uid(),
      follow_up_patient_end_seen_at = null,
      follow_up_doctor_end_seen_at = null,
      updated_at = ended_at_value
  where id = b.id;

  update public.chat_rooms
  set is_active = false,
      updated_at = ended_at_value
  where booking_id = b.id;

  return jsonb_build_object(
    'booking_id', b.id,
    'patient_id', b.patient_id,
    'doctor_id', b.doctor_id,
    'follow_up_ended_at', ended_at_value
  );
end;
$$;

create or replace function public.acknowledge_consultation_follow_up_end(
  p_booking_id uuid
)
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

  if not found or b.follow_up_ended_at is null then
    raise exception 'Completed follow-up not found';
  end if;

  if auth.uid() = b.patient_id then
    update public.bookings
    set follow_up_patient_end_seen_at = coalesce(
          follow_up_patient_end_seen_at,
          now()
        )
    where id = b.id;
  elsif auth.uid() = b.doctor_id then
    update public.bookings
    set follow_up_doctor_end_seen_at = coalesce(
          follow_up_doctor_end_seen_at,
          now()
        )
    where id = b.id;
  else
    raise exception 'Access denied';
  end if;
end;
$$;

revoke all on function public.schedule_consultation_follow_up(uuid, date)
  from public;
grant execute on function public.schedule_consultation_follow_up(uuid, date)
  to authenticated;

revoke all on function public.end_consultation_follow_up(uuid)
  from public;
grant execute on function public.end_consultation_follow_up(uuid)
  to authenticated;

revoke all on function public.acknowledge_consultation_follow_up_end(uuid)
  from public;
grant execute on function public.acknowledge_consultation_follow_up_end(uuid)
  to authenticated;

commit;

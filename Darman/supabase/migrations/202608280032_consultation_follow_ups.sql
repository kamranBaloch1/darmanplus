begin;

alter table public.bookings
  add column if not exists follow_up_date date,
  add column if not exists follow_up_scheduled_at timestamptz,
  add column if not exists follow_up_patient_seen_at timestamptz;

create index if not exists bookings_patient_follow_up_date_idx
  on public.bookings(patient_id, follow_up_date)
  where follow_up_date is not null and status = 'completed';

create index if not exists bookings_doctor_follow_up_date_idx
  on public.bookings(doctor_id, follow_up_date)
  where follow_up_date is not null and status = 'completed';

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
      updated_at = now()
  where id = b.id;

  return jsonb_build_object(
    'booking_id', b.id,
    'patient_id', b.patient_id,
    'doctor_id', b.doctor_id,
    'follow_up_date', p_follow_up_date,
    'follow_up_scheduled_at', now()
  );
end;
$$;

create or replace function public.acknowledge_consultation_follow_up(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bookings
  set follow_up_patient_seen_at = coalesce(follow_up_patient_seen_at, now())
  where id = p_booking_id
    and patient_id = auth.uid()
    and status = 'completed'
    and follow_up_date is not null;

  if not found then
    raise exception 'Follow-up not found';
  end if;
end;
$$;

revoke all on function public.schedule_consultation_follow_up(uuid, date)
  from public;
grant execute on function public.schedule_consultation_follow_up(uuid, date)
  to authenticated;

revoke all on function public.acknowledge_consultation_follow_up(uuid)
  from public;
grant execute on function public.acknowledge_consultation_follow_up(uuid)
  to authenticated;

commit;

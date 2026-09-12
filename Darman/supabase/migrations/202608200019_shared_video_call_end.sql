begin;

create or replace function public.mark_consultation_call_joined(p_booking_id uuid)
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
    raise exception 'The consultation has not started';
  end if;

  -- A previous call may have ended while the consultation remains active.
  -- The first participant joining again starts a clean call-presence cycle.
  if b.call_ended_at is not null then
    update public.bookings
    set patient_joined_at = null,
        doctor_joined_at = null,
        patient_left_at = null,
        doctor_left_at = null,
        call_started_at = null,
        call_ended_at = null,
        updated_at = now()
    where id = p_booking_id;

    select * into b
    from public.bookings
    where id = p_booking_id;
  end if;

  update public.bookings
  set patient_joined_at = case
        when auth.uid() = patient_id then now()
        else patient_joined_at
      end,
      doctor_joined_at = case
        when auth.uid() = doctor_id then now()
        else doctor_joined_at
      end,
      patient_left_at = case
        when auth.uid() = patient_id then null
        else patient_left_at
      end,
      doctor_left_at = case
        when auth.uid() = doctor_id then null
        else doctor_left_at
      end,
      call_started_at = case
        when call_started_at is null
          and (patient_joined_at is not null or auth.uid() = patient_id)
          and (doctor_joined_at is not null or auth.uid() = doctor_id)
        then now()
        else call_started_at
      end,
      updated_at = now()
  where id = p_booking_id;
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
  if b.call_ended_at is not null then
    return;
  end if;

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
end;
$$;

revoke all on function public.end_active_video_call(uuid) from public;
grant execute on function public.end_active_video_call(uuid) to authenticated;
grant execute on function public.mark_consultation_call_joined(uuid) to authenticated;

commit;

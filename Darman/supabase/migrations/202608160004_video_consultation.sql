begin;

alter table public.bookings
  add column if not exists call_started_at timestamptz,
  add column if not exists call_ended_at timestamptz,
  add column if not exists patient_left_at timestamptz,
  add column if not exists doctor_left_at timestamptz;

create or replace function public.mark_consultation_call_joined(p_booking_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found or auth.uid() not in (b.patient_id, b.doctor_id) then raise exception 'Access denied'; end if;
  if b.status <> 'inProgress' then raise exception 'The consultation has not started'; end if;
  update public.bookings set
    patient_joined_at = case when auth.uid() = patient_id then coalesce(patient_joined_at, now()) else patient_joined_at end,
    doctor_joined_at = case when auth.uid() = doctor_id then coalesce(doctor_joined_at, now()) else doctor_joined_at end,
    patient_left_at = case when auth.uid() = patient_id then null else patient_left_at end,
    doctor_left_at = case when auth.uid() = doctor_id then null else doctor_left_at end,
    call_started_at = case
      when call_started_at is null and
        (patient_joined_at is not null or auth.uid() = patient_id) and
        (doctor_joined_at is not null or auth.uid() = doctor_id)
      then now() else call_started_at end,
    updated_at = now()
  where id = p_booking_id;
end;
$$;

create or replace function public.mark_consultation_call_left(p_booking_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found or auth.uid() not in (b.patient_id, b.doctor_id) then raise exception 'Access denied'; end if;
  update public.bookings set
    patient_left_at = case when auth.uid() = patient_id then now() else patient_left_at end,
    doctor_left_at = case when auth.uid() = doctor_id then now() else doctor_left_at end,
    updated_at = now()
  where id = p_booking_id;
end;
$$;

create or replace function public.end_video_consultation(p_booking_id uuid)
returns void language plpgsql security definer set search_path = public as $$
declare b public.bookings%rowtype;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if auth.uid() is null or auth.uid() <> b.doctor_id then raise exception 'Only the assigned doctor can end the consultation'; end if;
  if b.status <> 'inProgress' then raise exception 'The consultation is not in progress'; end if;
  update public.bookings set status = 'completed', completed_at = now(), call_ended_at = now(), updated_at = now()
  where id = p_booking_id;
end;
$$;

grant execute on function public.mark_consultation_call_joined(uuid) to authenticated;
grant execute on function public.mark_consultation_call_left(uuid) to authenticated;
grant execute on function public.end_video_consultation(uuid) to authenticated;

commit;

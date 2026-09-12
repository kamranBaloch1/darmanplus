begin;

create or replace function public.request_consultation_start(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  conflicting_booking public.bookings%rowtype;
  active_patient_name text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id;

  if not found or auth.uid() <> b.doctor_id then
    raise exception 'Only the doctor can request consultation start';
  end if;

  -- Serialise every consultation-start operation for this doctor, including
  -- requests coming from another device at the same moment.
  perform pg_advisory_xact_lock(
    hashtextextended('doctor-consultation:' || b.doctor_id::text, 0)
  );

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if b.status <> 'accepted' then
    raise exception 'This appointment is not ready to start';
  end if;

  -- Repeated taps for the same unexpired request are idempotent.
  if b.session_start_status = 'pending'
     and b.session_start_requested_at > now() - interval '1 hour' then
    return;
  end if;

  select * into conflicting_booking
  from public.bookings
  where doctor_id = b.doctor_id
    and id <> p_booking_id
    and (
      status = 'inProgress'
      or (
        status = 'accepted'
        and session_start_status = 'pending'
        and session_start_requested_at > now() - interval '1 hour'
      )
    )
  order by
    case when status = 'inProgress' then 0 else 1 end,
    coalesce(started_at, session_start_requested_at, created_at) desc
  limit 1;

  if found then
    select coalesce(nullif(trim(name), ''), 'another patient')
    into active_patient_name
    from public.users
    where uid = conflicting_booking.patient_id;

    if conflicting_booking.status = 'inProgress' then
      raise exception 'A consultation is already active with %',
        coalesce(active_patient_name, 'another patient');
    end if;

    raise exception 'A consultation start request is already pending with %',
      coalesce(active_patient_name, 'another patient');
  end if;

  update public.bookings
  set session_start_status = 'pending',
      session_start_requested_at = now(),
      session_start_responded_at = null,
      updated_at = now()
  where id = p_booking_id;
end;
$$;

create or replace function public.respond_to_consultation_start(
  p_booking_id uuid,
  p_accept boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  conflicting_booking public.bookings%rowtype;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id;

  if not found or auth.uid() <> b.patient_id then
    raise exception 'Only the patient can answer this request';
  end if;

  perform pg_advisory_xact_lock(
    hashtextextended('doctor-consultation:' || b.doctor_id::text, 0)
  );

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if b.status <> 'accepted' or b.session_start_status <> 'pending' then
    raise exception 'This consultation-start request is no longer active';
  end if;
  if b.session_start_requested_at is null
     or b.session_start_requested_at <= now() - interval '1 hour' then
    update public.bookings
    set session_start_status = 'none',
        session_start_responded_at = now(),
        updated_at = now()
    where id = p_booking_id;
    raise exception 'This consultation-start request has expired';
  end if;

  if p_accept then
    select * into conflicting_booking
    from public.bookings
    where doctor_id = b.doctor_id
      and id <> p_booking_id
      and status = 'inProgress'
    limit 1;

    if found then
      raise exception 'The doctor already has an active consultation. Please try again after it ends';
    end if;

    update public.bookings
    set status = 'inProgress',
        started_at = coalesce(started_at, now()),
        session_start_responded_at = now(),
        updated_at = now()
    where id = p_booking_id;
  else
    update public.bookings
    set session_start_status = 'declined',
        session_start_responded_at = now(),
        updated_at = now()
    where id = p_booking_id;
  end if;
end;
$$;

revoke all on function public.request_consultation_start(uuid) from public;
revoke all on function public.respond_to_consultation_start(uuid, boolean) from public;
grant execute on function public.request_consultation_start(uuid) to authenticated;
grant execute on function public.respond_to_consultation_start(uuid, boolean) to authenticated;

commit;

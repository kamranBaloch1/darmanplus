begin;

create or replace function public.start_consultation_video_call(
  p_booking_id uuid
)
returns uuid
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  booking public.bookings%rowtype;
  existing_invite public.consultation_call_invites%rowtype;
  conflicting_invite public.consultation_call_invites%rowtype;
  caller_name_value text;
  callee_name_value text;
  callee_id_value uuid;
  invite_id uuid;
  first_lock bigint;
  second_lock bigint;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  follow_up_open boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into booking
  from public.bookings
  where id = p_booking_id;

  if not found or auth.uid() not in (booking.patient_id, booking.doctor_id) then
    raise exception 'Access denied';
  end if;

  follow_up_open := booking.status = 'completed'
    and booking.follow_up_date is not null
    and booking.follow_up_date <= local_today
    and booking.follow_up_ended_at is null;
  if booking.status <> 'inProgress' and not follow_up_open then
    raise exception 'The consultation chat is not open for calls';
  end if;

  callee_id_value := case
    when auth.uid() = booking.doctor_id then booking.patient_id
    else booking.doctor_id
  end;

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

  update public.consultation_call_invites i
  set status = 'ended', updated_at = now()
  from public.bookings b
  where i.booking_id = b.id
    and i.status = 'accepted'
    and (
      auth.uid() in (i.caller_id, i.callee_id)
      or callee_id_value in (i.caller_id, i.callee_id)
    )
    and (
      b.status not in ('inProgress', 'completed')
      or (
        b.status = 'completed'
        and (
          b.follow_up_date is null
          or b.follow_up_date > local_today
          or b.follow_up_ended_at is not null
        )
      )
      or i.updated_at < now() - interval '2 hours'
    );

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
    if auth.uid() in (conflicting_invite.caller_id, conflicting_invite.callee_id) then
      raise exception 'You are currently on another call';
    end if;
    raise exception 'This user is currently on another call';
  end if;

  select coalesce(nullif(raw_user_meta_data ->> 'full_name', ''), nullif(raw_user_meta_data ->> 'name', ''), nullif(email, ''), 'Caller')
  into caller_name_value
  from auth.users
  where id = auth.uid();

  select coalesce(nullif(raw_user_meta_data ->> 'full_name', ''), nullif(raw_user_meta_data ->> 'name', ''), nullif(email, ''), 'Participant')
  into callee_name_value
  from auth.users
  where id = callee_id_value;

  insert into public.consultation_call_invites (
    booking_id, caller_id, callee_id, caller_name, callee_name,
    caller_is_doctor, callee_is_doctor
  ) values (
    p_booking_id, auth.uid(), callee_id_value,
    coalesce(caller_name_value, 'Caller'),
    coalesce(callee_name_value, 'Participant'),
    auth.uid() = booking.doctor_id,
    callee_id_value = booking.doctor_id
  ) returning id into invite_id;

  return invite_id;
exception
  when unique_violation then
    raise exception 'A call is already active for this consultation';
end;
$$;

revoke all on function public.start_consultation_video_call(uuid) from public;
grant execute on function public.start_consultation_video_call(uuid) to authenticated;

commit;

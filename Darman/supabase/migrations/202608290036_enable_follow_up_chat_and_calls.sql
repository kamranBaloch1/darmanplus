begin;

-- Follow-ups reuse the original room and timeline. Older scheduled follow-ups
-- may have inherited a closed room before follow-up support was added.
update public.chat_rooms as room
set is_active = true,
    updated_at = now()
from public.bookings as booking
where room.booking_id = booking.id
  and booking.status = 'completed'
  and booking.follow_up_date is not null
  and booking.follow_up_ended_at is null;

grant select, insert on public.chat_messages to authenticated;
grant select on public.chat_rooms to authenticated;

drop policy if exists "Participants can view open follow-up rooms"
  on public.chat_rooms;
create policy "Participants can view open follow-up rooms"
  on public.chat_rooms
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.bookings as booking
      where booking.id = chat_rooms.booking_id
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and booking.status = 'completed'
        and booking.follow_up_date <=
          (now() at time zone 'Asia/Karachi')::date
        and booking.follow_up_ended_at is null
    )
  );

drop policy if exists "Participants can view open follow-up messages"
  on public.chat_messages;
create policy "Participants can view open follow-up messages"
  on public.chat_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.chat_rooms as room
      join public.bookings as booking on booking.id = room.booking_id
      where room.id = chat_messages.chat_room_id
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and booking.status = 'completed'
        and booking.follow_up_date <=
          (now() at time zone 'Asia/Karachi')::date
        and booking.follow_up_ended_at is null
    )
  );

drop policy if exists "Participants can send open follow-up messages"
  on public.chat_messages;
create policy "Participants can send open follow-up messages"
  on public.chat_messages
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.chat_rooms as room
      join public.bookings as booking on booking.id = room.booking_id
      where room.id = chat_messages.chat_room_id
        and booking.id = chat_messages.booking_id
        and room.is_active = true
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and booking.status = 'completed'
        and booking.follow_up_date <=
          (now() at time zone 'Asia/Karachi')::date
        and booking.follow_up_ended_at is null
    )
  );

create or replace function public.ensure_chat_room(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  booking public.bookings%rowtype;
  room_id uuid;
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

  if booking.status not in ('pending', 'accepted', 'inProgress')
     and not follow_up_open then
    raise exception 'This consultation chat is closed';
  end if;

  select id into room_id
  from public.chat_rooms
  where booking_id = booking.id
  limit 1;

  if room_id is null then
    insert into public.chat_rooms (
      booking_id,
      patient_id,
      doctor_id,
      is_active
    ) values (
      booking.id,
      booking.patient_id,
      booking.doctor_id,
      true
    )
    returning id into room_id;
  elsif follow_up_open then
    update public.chat_rooms
    set is_active = true,
        updated_at = now()
    where id = room_id;
  end if;

  return room_id;
end;
$$;

revoke all on function public.ensure_chat_room(uuid) from public;
grant execute on function public.ensure_chat_room(uuid) to authenticated;

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

  first_lock := hashtextextended(
    least(auth.uid()::text, callee_id_value::text),
    0
  );
  second_lock := hashtextextended(
    greatest(auth.uid()::text, callee_id_value::text),
    0
  );
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
    auth.uid() = booking.doctor_id,
    callee_id_value = booking.doctor_id
  ) returning id into invite_id;

  return invite_id;
exception
  when unique_violation then
    raise exception 'A call is already active for this consultation';
end;
$$;

create or replace function public.mark_consultation_call_joined(
  p_booking_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  booking public.bookings%rowtype;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  follow_up_open boolean;
begin
  select * into booking
  from public.bookings
  where id = p_booking_id
  for update;

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

  if booking.call_ended_at is not null then
    update public.bookings
    set patient_joined_at = null,
        doctor_joined_at = null,
        patient_left_at = null,
        doctor_left_at = null,
        call_started_at = null,
        call_ended_at = null,
        updated_at = now()
    where id = p_booking_id;

    select * into booking
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
  booking public.bookings%rowtype;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  follow_up_open boolean;
begin
  select * into booking
  from public.bookings
  where id = p_booking_id
  for update;

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
  if booking.call_ended_at is not null then
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

  update public.consultation_call_invites
  set status = 'ended',
      updated_at = now()
  where booking_id = p_booking_id
    and status = 'accepted';
end;
$$;

create or replace function public.close_calls_when_follow_up_ends()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.follow_up_ended_at is null and new.follow_up_ended_at is not null then
    update public.consultation_call_invites
    set status = case
          when status = 'accepted' then 'ended'
          else 'cancelled'
        end,
        responded_at = coalesce(responded_at, now()),
        updated_at = now()
    where booking_id = new.id
      and status in ('ringing', 'accepted');
  end if;
  return new;
end;
$$;

drop trigger if exists close_calls_when_follow_up_ends on public.bookings;
create trigger close_calls_when_follow_up_ends
after update of follow_up_ended_at on public.bookings
for each row execute function public.close_calls_when_follow_up_ends();

revoke all on function public.start_consultation_video_call(uuid) from public;
revoke all on function public.mark_consultation_call_joined(uuid) from public;
revoke all on function public.end_active_video_call(uuid) from public;
revoke all on function public.close_calls_when_follow_up_ends() from public;
grant execute on function public.start_consultation_video_call(uuid)
  to authenticated;
grant execute on function public.mark_consultation_call_joined(uuid)
  to authenticated;
grant execute on function public.end_active_video_call(uuid)
  to authenticated;

commit;

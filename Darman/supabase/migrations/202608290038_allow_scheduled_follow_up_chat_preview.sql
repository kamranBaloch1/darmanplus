begin;

drop policy if exists "Participants can view open follow-up rooms"
  on public.chat_rooms;
create policy "Participants can view scheduled follow-up rooms"
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
        and booking.follow_up_date is not null
        and booking.follow_up_ended_at is null
    )
  );

drop policy if exists "Participants can view open follow-up messages"
  on public.chat_messages;
create policy "Participants can view scheduled follow-up messages"
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
        and booking.follow_up_date is not null
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
  follow_up_scheduled boolean;
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

  follow_up_scheduled := booking.status = 'completed'
    and booking.follow_up_date is not null
    and booking.follow_up_ended_at is null;
  follow_up_open := follow_up_scheduled
    and booking.follow_up_date <= local_today;

  if booking.status not in ('pending', 'accepted', 'inProgress')
     and not follow_up_scheduled then
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
      booking.status in ('pending', 'accepted', 'inProgress')
        or follow_up_open
    )
    returning id into room_id;
  elsif follow_up_scheduled then
    update public.chat_rooms
    set is_active = follow_up_open,
        updated_at = now()
    where id = room_id;
  end if;

  return room_id;
end;
$$;

revoke all on function public.ensure_chat_room(uuid) from public;
grant execute on function public.ensure_chat_room(uuid) to authenticated;

commit;

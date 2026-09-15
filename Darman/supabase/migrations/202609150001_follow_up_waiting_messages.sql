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
  history_visible boolean;
  active_chat boolean;
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

  history_visible := (
      booking.status = 'completed'
      and booking.follow_up_ended_at is null
    )
    or booking.status = 'cancelled';
  active_chat := booking.status in ('pending', 'accepted', 'inProgress')
    or (
      booking.status = 'completed'
      and booking.follow_up_date is not null
      and booking.follow_up_date <= local_today
      and booking.follow_up_ended_at is null
    );

  if booking.status not in ('pending', 'accepted', 'inProgress')
     and not history_visible then
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
      active_chat
    )
    returning id into room_id;
  else
    update public.chat_rooms
    set is_active = active_chat,
        updated_at = now()
    where id = room_id;
  end if;

  return room_id;
end;
$$;

create or replace function public.send_follow_up_chat_message(
  p_message_id uuid,
  p_room_id uuid,
  p_booking_id uuid,
  p_type text,
  p_text text default null,
  p_media_url text default null,
  p_file_name text default null,
  p_file_size_bytes bigint default null,
  p_mime_type text default null,
  p_voice_duration_seconds integer default null,
  p_reply_to_message_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  booking public.bookings%rowtype;
  room public.chat_rooms%rowtype;
  inserted public.chat_messages%rowtype;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  post_consultation_chat boolean := false;
  waiting_message_count integer := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into booking
  from public.bookings
  where id = p_booking_id
  for share;

  if not found or auth.uid() not in (booking.patient_id, booking.doctor_id) then
    raise exception 'Access denied';
  end if;

  post_consultation_chat := booking.status = 'completed'
    and booking.follow_up_date is null
    and booking.follow_up_ended_at is null;

  if booking.status <> 'completed'
     or booking.follow_up_ended_at is not null then
    raise exception 'This chat is closed';
  end if;

  if post_consultation_chat or booking.follow_up_date > local_today then
    select count(*) into waiting_message_count
    from public.chat_messages message
    where message.booking_id = booking.id
      and message.sender_id = auth.uid()
      and message.type <> 'system'
      and message.created_at >= coalesce(
        booking.follow_up_scheduled_at,
        booking.completed_at,
        '-infinity'::timestamptz
      );

    if waiting_message_count >= 5 then
      raise exception 'Limited message allowance reached';
    end if;
  end if;

  select * into room
  from public.chat_rooms
  where booking_id = booking.id
  order by created_at
  limit 1
  for update;

  if not found then
    insert into public.chat_rooms (
      booking_id,
      patient_id,
      doctor_id,
      is_active
    ) values (
      booking.id,
      booking.patient_id,
      booking.doctor_id,
      booking.follow_up_date is not null
        and booking.follow_up_date <= local_today
    )
    returning * into room;
  else
    update public.chat_rooms
    set is_active = booking.follow_up_date is not null
          and booking.follow_up_date <= local_today,
        updated_at = now()
    where id = room.id
    returning * into room;
  end if;

  if room.patient_id <> booking.patient_id
     or room.doctor_id <> booking.doctor_id then
    raise exception 'Invalid chat room';
  end if;

  if p_type not in ('text', 'image', 'file', 'voice') then
    raise exception 'Unsupported message type';
  end if;
  if p_type = 'text' and nullif(btrim(p_text), '') is null then
    raise exception 'Message cannot be empty';
  end if;
  if length(coalesce(p_text, '')) > 4000 then
    raise exception 'Message is too long';
  end if;
  if p_type in ('image', 'file', 'voice')
     and nullif(btrim(p_media_url), '') is null then
    raise exception 'Attachment is required';
  end if;
  if p_reply_to_message_id is not null and not exists (
    select 1
    from public.chat_messages reply
    where reply.id = p_reply_to_message_id
      and reply.chat_room_id = room.id
  ) then
    raise exception 'Reply message not found';
  end if;

  insert into public.chat_messages (
    id,
    chat_room_id,
    booking_id,
    sender_id,
    type,
    status,
    text,
    media_url,
    file_name,
    file_size_bytes,
    mime_type,
    voice_duration_seconds,
    reply_to_message_id,
    created_at,
    updated_at
  ) values (
    p_message_id,
    room.id,
    booking.id,
    auth.uid(),
    p_type,
    'sent',
    nullif(btrim(p_text), ''),
    nullif(btrim(p_media_url), ''),
    nullif(btrim(p_file_name), ''),
    p_file_size_bytes,
    nullif(btrim(p_mime_type), ''),
    p_voice_duration_seconds,
    p_reply_to_message_id,
    now(),
    now()
  )
  on conflict (id) do nothing
  returning * into inserted;

  if not found then
    select * into inserted
    from public.chat_messages existing
    where existing.id = p_message_id
      and existing.chat_room_id = room.id
      and existing.booking_id = booking.id
      and existing.sender_id = auth.uid();

    if not found then
      raise exception 'Message ID is already in use';
    end if;
  end if;

  return to_jsonb(inserted);
end;
$$;

revoke all on function public.send_follow_up_chat_message(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  bigint,
  text,
  integer,
  uuid
) from public;
grant execute on function public.send_follow_up_chat_message(
  uuid,
  uuid,
  uuid,
  text,
  text,
  text,
  text,
  bigint,
  text,
  integer,
  uuid
) to authenticated;

revoke all on function public.ensure_chat_room(uuid) from public;
grant execute on function public.ensure_chat_room(uuid) to authenticated;

drop policy if exists "Participants can view completed consultation rooms"
  on public.chat_rooms;
create policy "Participants can view completed consultation rooms"
  on public.chat_rooms
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.bookings as booking
      where booking.id = chat_rooms.booking_id
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and (
          (
            booking.status = 'completed'
            and booking.follow_up_ended_at is null
          )
          or booking.status = 'cancelled'
        )
    )
  );

drop policy if exists "Participants can view completed consultation messages"
  on public.chat_messages;
create policy "Participants can view completed consultation messages"
  on public.chat_messages
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.bookings as booking
      where booking.id = chat_messages.booking_id
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and (
          (
            booking.status = 'completed'
            and booking.follow_up_ended_at is null
          )
          or booking.status = 'cancelled'
        )
    )
  );

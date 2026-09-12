begin;

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
  if booking.status <> 'completed'
     or booking.follow_up_date is null
     or booking.follow_up_date > local_today
     or booking.follow_up_ended_at is not null then
    raise exception 'The follow-up chat is not open';
  end if;

  select * into room
  from public.chat_rooms
  where id = p_room_id
    and booking_id = booking.id
  for update;

  if not found then
    raise exception 'Chat room not found';
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

  if not room.is_active then
    update public.chat_rooms
    set is_active = true,
        updated_at = now()
    where id = room.id;
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

commit;

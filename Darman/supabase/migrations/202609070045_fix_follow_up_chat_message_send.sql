begin;

grant select on public.chat_rooms to authenticated;
grant select, insert on public.chat_messages to authenticated;

-- Follow-up chats are controlled by the booking date. Do not let an older
-- closed chat room block messages once the follow-up date has arrived.
update public.chat_rooms as room
set is_active = true,
    updated_at = now()
from public.bookings as booking
where room.booking_id = booking.id
  and booking.status = 'completed'
  and booking.follow_up_date is not null
  and booking.follow_up_date <= (now() at time zone 'Asia/Karachi')::date
  and booking.follow_up_ended_at is null;

-- Some live databases had an older chat_messages trigger that rejected every
-- completed booking before follow-up chat support existed. Remove only triggers
-- whose trigger function contains that stale booking-message rejection.
do $$
declare
  trigger_record record;
begin
  for trigger_record in
    select trigger_item.tgname
    from pg_trigger trigger_item
    join pg_class table_item on table_item.oid = trigger_item.tgrelid
    join pg_namespace schema_item on schema_item.oid = table_item.relnamespace
    join pg_proc proc_item on proc_item.oid = trigger_item.tgfoid
    where schema_item.nspname = 'public'
      and table_item.relname = 'chat_messages'
      and not trigger_item.tgisinternal
      and (
        lower(pg_get_functiondef(proc_item.oid)) like '%cannot be sent for this booking%'
        or lower(pg_get_functiondef(proc_item.oid)) like '%can not be sent for this booking%'
        or lower(pg_get_functiondef(proc_item.oid)) like '%cant send%booking%'
        or lower(pg_get_functiondef(proc_item.oid)) like '%can''t send%booking%'
      )
  loop
    execute format(
      'drop trigger if exists %I on public.chat_messages',
      trigger_record.tgname
    );
  end loop;
end;
$$;

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
      booking.status in ('pending', 'accepted', 'inProgress') or follow_up_open
    )
    returning id into room_id;
  else
    update public.chat_rooms
    set is_active = booking.status in ('pending', 'accepted', 'inProgress')
          or follow_up_open,
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
      true
    )
    returning * into room;
  else
    update public.chat_rooms
    set is_active = true,
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

drop policy if exists "Booking state gates all chat message inserts"
  on public.chat_messages;
create policy "Booking state gates all chat message inserts"
  on public.chat_messages
  as restrictive
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
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and (
          booking.status in ('pending', 'accepted', 'inProgress')
          or (
            booking.status = 'completed'
            and booking.follow_up_date is not null
            and booking.follow_up_date <=
              (now() at time zone 'Asia/Karachi')::date
            and booking.follow_up_ended_at is null
          )
        )
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
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and booking.status = 'completed'
        and booking.follow_up_date is not null
        and booking.follow_up_date <=
          (now() at time zone 'Asia/Karachi')::date
        and booking.follow_up_ended_at is null
    )
  );

revoke all on function public.ensure_chat_room(uuid) from public;
grant execute on function public.ensure_chat_room(uuid) to authenticated;

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

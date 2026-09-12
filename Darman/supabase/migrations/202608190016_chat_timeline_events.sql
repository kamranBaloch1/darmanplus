begin;

alter table public.chat_messages
  add column if not exists system_event_key text;

create unique index if not exists chat_messages_system_event_key_unique
  on public.chat_messages(system_event_key)
  where system_event_key is not null;

create or replace function public.add_booking_chat_system_message(
  p_booking_id uuid,
  p_event_key text,
  p_text text,
  p_created_at timestamptz default now()
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  room_id uuid;
begin
  select id into room_id
  from public.chat_rooms
  where booking_id = p_booking_id
  order by created_at asc
  limit 1;

  -- An appointment may be cancelled before its chat room has been created.
  if room_id is null then
    return;
  end if;

  insert into public.chat_messages (
    id,
    chat_room_id,
    booking_id,
    sender_id,
    type,
    status,
    text,
    system_event_key,
    created_at,
    updated_at
  ) values (
    gen_random_uuid(),
    room_id,
    p_booking_id,
    null,
    'system',
    'sent',
    p_text,
    p_event_key,
    coalesce(p_created_at, now()),
    coalesce(p_created_at, now())
  )
  on conflict (system_event_key) where system_event_key is not null do nothing;
end;
$$;

create or replace function public.log_booking_chat_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.session_start_status = 'pending'
     and (old.session_start_requested_at is distinct from new.session_start_requested_at) then
    perform public.add_booking_chat_system_message(
      new.id,
      'session-start-request:' || new.id || ':' || new.session_start_requested_at::text,
      'Doctor requested to start the consultation.',
      new.session_start_requested_at
    );
  end if;

  if new.session_start_status = 'declined'
     and old.session_start_status is distinct from new.session_start_status then
    perform public.add_booking_chat_system_message(
      new.id,
      'session-start-declined:' || new.id || ':' || coalesce(new.session_start_responded_at, now())::text,
      'The consultation start request was declined.',
      coalesce(new.session_start_responded_at, now())
    );
  end if;

  if new.status = 'inProgress' and old.status is distinct from new.status then
    perform public.add_booking_chat_system_message(
      new.id,
      'consultation-started:' || new.id,
      'Consultation started.',
      coalesce(new.started_at, now())
    );
  end if;

  if new.call_started_at is not null and old.call_started_at is null then
    perform public.add_booking_chat_system_message(
      new.id,
      'video-call-started:' || new.id || ':' || new.call_started_at::text,
      'Video call started.',
      new.call_started_at
    );
  end if;

  if new.status = 'cancelled' and old.status is distinct from new.status then
    perform public.add_booking_chat_system_message(
      new.id,
      'appointment-cancelled:' || new.id,
      'Appointment cancelled.',
      coalesce(new.cancelled_at, now())
    );
  end if;

  if new.call_ended_at is not null and old.call_ended_at is null then
    perform public.add_booking_chat_system_message(
      new.id,
      'video-call-ended:' || new.id || ':' || new.call_ended_at::text,
      'Video call ended.',
      new.call_ended_at
    );
  end if;

  if new.status = 'completed' and old.status is distinct from new.status then
    perform public.add_booking_chat_system_message(
      new.id,
      'consultation-ended:' || new.id,
      'Consultation completed.',
      coalesce(new.completed_at, now())
    );
  end if;

  return new;
end;
$$;

drop trigger if exists bookings_chat_timeline_events on public.bookings;
create trigger bookings_chat_timeline_events
after update on public.bookings
for each row execute function public.log_booking_chat_events();

create or replace function public.log_video_invite_chat_events()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'UPDATE'
     and new.status in ('declined', 'cancelled', 'expired')
     and old.status is distinct from new.status then
    perform public.add_booking_chat_system_message(
      new.booking_id,
      'video-call-invite:' || new.id || ':' || new.status,
      case new.status
        when 'declined' then 'Video call declined.'
        when 'cancelled' then 'Video call cancelled.'
        else 'Video call missed.'
      end,
      coalesce(new.responded_at, new.updated_at, now())
    );
  end if;
  return new;
end;
$$;

drop trigger if exists video_invites_chat_timeline_events
  on public.consultation_call_invites;
create trigger video_invites_chat_timeline_events
after update on public.consultation_call_invites
for each row execute function public.log_video_invite_chat_events();

revoke all on function public.add_booking_chat_system_message(uuid, text, text, timestamptz)
  from public;

commit;

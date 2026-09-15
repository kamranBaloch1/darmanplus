create or replace function public.enforce_pre_session_chat_message_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  booking public.bookings%rowtype;
  existing_count integer := 0;
begin
  if new.type = 'system' then
    return new;
  end if;

  select * into booking
  from public.bookings
  where id = new.booking_id;

  if not found then
    return new;
  end if;

  if booking.status in ('pending', 'accepted')
     and booking.session_start_status is distinct from 'accepted'
     and booking.started_at is null then
    select count(*) into existing_count
    from public.chat_messages message
    where message.booking_id = new.booking_id
      and message.sender_id = new.sender_id
      and message.type <> 'system';

    if existing_count >= 15 then
      raise exception 'Pre-consultation message limit reached';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists enforce_pre_session_chat_message_limit
  on public.chat_messages;
create trigger enforce_pre_session_chat_message_limit
before insert on public.chat_messages
for each row execute function public.enforce_pre_session_chat_message_limit();

revoke all on function public.enforce_pre_session_chat_message_limit()
  from public;

begin;

create or replace function public.enforce_pre_session_chat_message_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  booking_status text;
begin
  if new.type = 'system' then return new; end if;

  select status into booking_status
  from public.bookings
  where id = new.booking_id;

  if booking_status = 'pending' then
    raise exception 'Chat unlocks after the doctor accepts the consultation';
  end if;

  return new;
end;
$$;

commit;

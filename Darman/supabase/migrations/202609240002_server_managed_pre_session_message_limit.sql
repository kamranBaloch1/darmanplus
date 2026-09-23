begin;

create table if not exists public.app_runtime_settings (
  setting_key text primary key,
  integer_value integer not null check (integer_value > 0),
  updated_at timestamptz not null default now()
);

alter table public.app_runtime_settings enable row level security;
revoke all on table public.app_runtime_settings from anon, authenticated;

insert into public.app_runtime_settings (setting_key, integer_value, updated_at)
values ('pre_session_message_limit', 6, now())
on conflict (setting_key) do update
set integer_value = excluded.integer_value,
    updated_at = now();

create or replace function public.get_pre_session_message_limit()
returns integer
language sql
stable
security definer
set search_path = public
as $$
  select integer_value
  from public.app_runtime_settings
  where setting_key = 'pre_session_message_limit';
$$;

revoke all on function public.get_pre_session_message_limit() from public;
grant execute on function public.get_pre_session_message_limit()
  to authenticated, service_role;

create or replace function public.enforce_pre_session_chat_message_limit()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  booking public.bookings%rowtype;
  existing_count integer := 0;
  message_limit integer;
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
    select integer_value into message_limit
    from public.app_runtime_settings
    where setting_key = 'pre_session_message_limit';

    if message_limit is null then
      raise exception 'Pre-consultation message limit is not configured';
    end if;

    perform pg_advisory_xact_lock(
      hashtextextended(new.booking_id::text || ':' || new.sender_id::text, 0)
    );

    select count(*) into existing_count
    from public.chat_messages message
    where message.booking_id = new.booking_id
      and message.sender_id = new.sender_id
      and message.type <> 'system';

    if existing_count >= message_limit then
      raise exception 'Pre-consultation message limit reached';
    end if;
  end if;

  return new;
end;
$$;

commit;

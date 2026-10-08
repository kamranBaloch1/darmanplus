begin;

-- Any client version that writes accepted is normalized before storage.
create or replace function public.normalize_accepted_booking_to_in_progress()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'accepted' then
    new.status := 'inProgress';
    new.accepted_at := coalesce(new.accepted_at, now());
    new.started_at := coalesce(new.started_at, new.accepted_at, now());
    new.session_start_status := 'none';
    new.session_start_responded_at := coalesce(
      new.session_start_responded_at,
      new.accepted_at,
      now()
    );
  end if;
  return new;
end;
$$;

drop trigger if exists normalize_accepted_booking_to_in_progress
  on public.bookings;
create trigger normalize_accepted_booking_to_in_progress
before insert or update on public.bookings
for each row execute function public.normalize_accepted_booking_to_in_progress();

-- Repair rows created before this trigger was installed.
update public.bookings
set status = 'inProgress',
    accepted_at = coalesce(accepted_at, now()),
    started_at = coalesce(started_at, accepted_at, now()),
    session_start_status = 'none',
    session_start_responded_at = coalesce(session_start_responded_at, accepted_at, now()),
    updated_at = now()
where status = 'accepted';

-- Pending requests have no chat. Once normalized to inProgress, chat is free.
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

-- Accepted-not-started no longer exists, so its reminder must stay disabled.
select cron.unschedule(jobid)
from cron.job
where jobname = 'send-darman-accepted-consultation-reminders';

drop index if exists public.bookings_accepted_not_started_reminder_idx;

commit;

begin;

create or replace function public.normalize_accepted_booking_to_in_progress()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status = 'accepted' and old.status = 'pending' then
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
before update of status on public.bookings
for each row execute function public.normalize_accepted_booking_to_in_progress();

update public.bookings
set status = 'inProgress',
    started_at = coalesce(started_at, accepted_at, now()),
    session_start_status = 'none',
    session_start_responded_at = coalesce(session_start_responded_at, accepted_at, now()),
    updated_at = now()
where status = 'accepted';

select cron.unschedule(jobid)
from cron.job
where jobname = 'send-darman-accepted-consultation-reminders';

drop index if exists public.bookings_accepted_not_started_reminder_idx;

commit;

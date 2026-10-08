begin;

-- Remove the obsolete accepted waiting state from existing live bookings.
update public.bookings
set status = 'inProgress',
    started_at = coalesce(started_at, accepted_at, now()),
    session_start_status = 'none',
    session_start_responded_at = coalesce(session_start_responded_at, accepted_at, now()),
    updated_at = now()
where status = 'accepted';

commit;

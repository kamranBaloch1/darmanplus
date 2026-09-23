begin;

create or replace function public.claim_pending_consultation_request_reminders()
returns table (
  doctor_id uuid,
  request_count bigint,
  booking_ids uuid[]
)
language plpgsql
security definer
set search_path = public
as $$
begin
  return query
  with due as (
    select b.id
    from public.bookings b
    where b.status = 'pending'
      and b.created_at <= now() - interval '10 minutes'
      and (
        b.pending_request_reminded_at is null
        or b.pending_request_reminded_at <= now() - interval '10 minutes'
      )
    order by b.created_at
    for update skip locked
    limit 1000
  ), claimed as (
    update public.bookings b
    set pending_request_reminded_at = now()
    from due
    where b.id = due.id
      and b.status = 'pending'
    returning b.id, b.doctor_id
  )
  select
    claimed.doctor_id,
    count(*)::bigint,
    array_agg(claimed.id order by claimed.id)
  from claimed
  group by claimed.doctor_id;
end;
$$;

commit;

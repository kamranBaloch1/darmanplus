begin;

alter table public.bookings
  add column if not exists pending_request_reminded_at timestamptz;

create index if not exists bookings_pending_request_reminder_idx
  on public.bookings (created_at, pending_request_reminded_at)
  where status = 'pending';

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
      and b.created_at <= now() - interval '1 hour'
      and (
        b.pending_request_reminded_at is null
        or b.pending_request_reminded_at <= now() - interval '30 minutes'
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

create or replace function public.release_pending_consultation_request_reminders(
  p_booking_ids uuid[]
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.bookings
  set pending_request_reminded_at = null
  where id = any(p_booking_ids)
    and status = 'pending';
$$;

revoke all on function public.claim_pending_consultation_request_reminders()
  from public;
grant execute on function public.claim_pending_consultation_request_reminders()
  to service_role;

revoke all on function public.release_pending_consultation_request_reminders(uuid[])
  from public;
grant execute on function public.release_pending_consultation_request_reminders(uuid[])
  to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'send-darman-pending-consultation-reminders';

select cron.schedule(
  'send-darman-pending-consultation-reminders',
  '*/30 * * * *',
  $cron$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'darman_follow_up_project_url'
      ) || '/functions/v1/send-pending-consultation-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'darman_follow_up_publishable_key'
        ),
        'x-darman-cron-secret', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'darman_follow_up_cron_secret'
        )
      ),
      body := jsonb_build_object('scheduled_at', now()),
      timeout_milliseconds := 10000
    ) as request_id;
  $cron$
);

commit;

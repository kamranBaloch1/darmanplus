begin;

alter table public.bookings
  add column if not exists accepted_not_started_reminded_at timestamptz;

create index if not exists bookings_accepted_not_started_reminder_idx
  on public.bookings (accepted_at, accepted_not_started_reminded_at)
  where status = 'accepted' and started_at is null;

create or replace function public.claim_accepted_consultation_reminders()
returns table (
  doctor_id uuid,
  consultation_count bigint,
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
    where b.status = 'accepted'
      and b.started_at is null
      and b.accepted_at <= now() - interval '15 minutes'
      and (
        b.accepted_not_started_reminded_at is null
        or b.accepted_not_started_reminded_at <= now() - interval '15 minutes'
      )
    order by b.accepted_at
    for update skip locked
    limit 1000
  ), claimed as (
    update public.bookings b
    set accepted_not_started_reminded_at = now()
    from due
    where b.id = due.id
      and b.status = 'accepted'
      and b.started_at is null
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

create or replace function public.release_accepted_consultation_reminders(
  p_booking_ids uuid[]
)
returns void
language sql
security definer
set search_path = public
as $$
  update public.bookings
  set accepted_not_started_reminded_at = null
  where id = any(p_booking_ids)
    and status = 'accepted'
    and started_at is null;
$$;

revoke all on function public.claim_accepted_consultation_reminders()
  from public;
grant execute on function public.claim_accepted_consultation_reminders()
  to service_role;

revoke all on function public.release_accepted_consultation_reminders(uuid[])
  from public;
grant execute on function public.release_accepted_consultation_reminders(uuid[])
  to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'send-darman-accepted-consultation-reminders';

select cron.schedule(
  'send-darman-accepted-consultation-reminders',
  '*/15 * * * *',
  $cron$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'darman_follow_up_project_url'
      ) || '/functions/v1/send-accepted-consultation-reminders',
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

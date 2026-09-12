begin;

create extension if not exists pg_cron with schema pg_catalog;
create extension if not exists pg_net with schema extensions;

alter table public.bookings
  add column if not exists follow_up_day_patient_notified_at timestamptz,
  add column if not exists follow_up_day_doctor_notified_at timestamptz,
  add column if not exists follow_up_day_notification_claimed_at timestamptz;

create or replace function public.reset_consultation_follow_up_notifications()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.follow_up_date is distinct from old.follow_up_date
     or new.follow_up_scheduled_at is distinct from old.follow_up_scheduled_at then
    new.follow_up_day_patient_notified_at := null;
    new.follow_up_day_doctor_notified_at := null;
    new.follow_up_day_notification_claimed_at := null;
  end if;
  return new;
end;
$$;

drop trigger if exists reset_consultation_follow_up_notifications
  on public.bookings;
create trigger reset_consultation_follow_up_notifications
before update of follow_up_date, follow_up_scheduled_at on public.bookings
for each row execute function public.reset_consultation_follow_up_notifications();

create or replace function public.claim_due_consultation_follow_up_notifications()
returns table (
  booking_id uuid,
  patient_id uuid,
  doctor_id uuid,
  follow_up_date date,
  patient_notified_at timestamptz,
  doctor_notified_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  local_today date := (now() at time zone 'Asia/Karachi')::date;
begin
  return query
  with due as (
    select b.id
    from public.bookings b
    where b.status = 'completed'
      and b.follow_up_date = local_today
      and (
        b.follow_up_day_patient_notified_at is null
        or b.follow_up_day_doctor_notified_at is null
      )
      and (
        b.follow_up_day_notification_claimed_at is null
        or b.follow_up_day_notification_claimed_at < now() - interval '15 minutes'
      )
    order by b.follow_up_scheduled_at, b.id
    for update skip locked
    limit 100
  ), claimed as (
    update public.bookings b
    set follow_up_day_notification_claimed_at = now()
    from due
    where b.id = due.id
    returning
      b.id,
      b.patient_id,
      b.doctor_id,
      b.follow_up_date,
      b.follow_up_day_patient_notified_at,
      b.follow_up_day_doctor_notified_at
  )
  select
    claimed.id,
    claimed.patient_id,
    claimed.doctor_id,
    claimed.follow_up_date,
    claimed.follow_up_day_patient_notified_at,
    claimed.follow_up_day_doctor_notified_at
  from claimed;
end;
$$;

create or replace function public.finish_consultation_follow_up_notification(
  p_booking_id uuid,
  p_patient_sent boolean,
  p_doctor_sent boolean
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bookings
  set follow_up_day_patient_notified_at = case
        when p_patient_sent then coalesce(follow_up_day_patient_notified_at, now())
        else follow_up_day_patient_notified_at
      end,
      follow_up_day_doctor_notified_at = case
        when p_doctor_sent then coalesce(follow_up_day_doctor_notified_at, now())
        else follow_up_day_doctor_notified_at
      end,
      follow_up_day_notification_claimed_at = null
  where id = p_booking_id;
end;
$$;

revoke all on function public.claim_due_consultation_follow_up_notifications()
  from public;
grant execute on function public.claim_due_consultation_follow_up_notifications()
  to service_role;

revoke all on function public.finish_consultation_follow_up_notification(uuid, boolean, boolean)
  from public;
grant execute on function public.finish_consultation_follow_up_notification(uuid, boolean, boolean)
  to service_role;

do $$
begin
  if not exists (
    select 1 from vault.secrets where name = 'darman_follow_up_project_url'
  ) then
    perform vault.create_secret(
      'https://bnwvwlkiwgbtmvltzenp.supabase.co',
      'darman_follow_up_project_url'
    );
  end if;

  if not exists (
    select 1 from vault.secrets where name = 'darman_follow_up_publishable_key'
  ) then
    perform vault.create_secret(
      'sb_publishable_1Xfj4nBTsS8dkoLrlIZbTA_5h7eJEOQ',
      'darman_follow_up_publishable_key'
    );
  end if;
end;
$$;

select cron.unschedule(jobid)
from cron.job
where jobname = 'send-darman-follow-up-day-reminders';

select cron.schedule(
  'send-darman-follow-up-day-reminders',
  '5 * * * *',
  $cron$
    select net.http_post(
      url := (
        select decrypted_secret
        from vault.decrypted_secrets
        where name = 'darman_follow_up_project_url'
      ) || '/functions/v1/send-follow-up-day-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'darman_follow_up_publishable_key'
        )
      ),
      body := jsonb_build_object('scheduled_at', now()),
      timeout_milliseconds := 10000
    ) as request_id;
  $cron$
);

commit;

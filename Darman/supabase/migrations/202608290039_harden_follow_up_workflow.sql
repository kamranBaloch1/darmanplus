begin;

-- Serialize active bookings for the same patient/doctor pair. This keeps the
-- product rule database-enforced even when two devices submit simultaneously,
-- while still allowing a new paid booking beside a completed follow-up.
create or replace function public.prevent_duplicate_active_doctor_booking()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.status in ('pending', 'accepted', 'inProgress') then
    perform pg_advisory_xact_lock(
      hashtext(new.patient_id::text),
      hashtext(new.doctor_id::text)
    );

    if exists (
      select 1
      from public.bookings as existing
      where existing.patient_id = new.patient_id
        and existing.doctor_id = new.doctor_id
        and existing.status in ('pending', 'accepted', 'inProgress')
        and existing.id is distinct from new.id
    ) then
      raise unique_violation using
        message = 'You already have an active booking with this doctor';
    end if;
  end if;

  return new;
end;
$$;

drop trigger if exists prevent_duplicate_active_doctor_booking
  on public.bookings;
create trigger prevent_duplicate_active_doctor_booking
before insert or update of patient_id, doctor_id, status on public.bookings
for each row execute function public.prevent_duplicate_active_doctor_booking();

-- Follow-up lifecycle fields may only be changed through the guarded server
-- functions below (or by the trusted service role), never by a direct REST
-- update to a booking row.
create or replace function public.guard_consultation_follow_up_lifecycle()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if (
    new.follow_up_date is distinct from old.follow_up_date
    or new.follow_up_scheduled_at is distinct from old.follow_up_scheduled_at
    or new.follow_up_ended_at is distinct from old.follow_up_ended_at
    or new.follow_up_ended_by is distinct from old.follow_up_ended_by
  )
  and current_setting('darman.follow_up_lifecycle_write', true)
        is distinct from 'allowed'
  and coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Follow-up lifecycle changes must use the approved server action';
  end if;

  return new;
end;
$$;

drop trigger if exists guard_consultation_follow_up_lifecycle
  on public.bookings;
create trigger guard_consultation_follow_up_lifecycle
before update of follow_up_date, follow_up_scheduled_at,
  follow_up_ended_at, follow_up_ended_by on public.bookings
for each row execute function public.guard_consultation_follow_up_lifecycle();

create or replace function public.schedule_consultation_follow_up(
  p_booking_id uuid,
  p_follow_up_date date
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  scheduled_at_value timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;
  if auth.uid() <> b.doctor_id then
    raise exception 'Only the assigned doctor can schedule a follow-up';
  end if;
  if b.status <> 'completed' then
    raise exception 'Complete the consultation before scheduling a follow-up';
  end if;
  if b.follow_up_ended_at is not null then
    raise exception 'This follow-up has already ended and cannot be reopened';
  end if;
  if b.follow_up_date is not null and b.follow_up_date <= local_today then
    raise exception 'A started follow-up cannot be rescheduled';
  end if;
  if p_follow_up_date <= local_today then
    raise exception 'Choose a future follow-up date';
  end if;
  if p_follow_up_date > local_today + 365 then
    raise exception 'The follow-up date must be within one year';
  end if;

  scheduled_at_value := now();
  perform set_config('darman.follow_up_lifecycle_write', 'allowed', true);

  update public.bookings
  set follow_up_date = p_follow_up_date,
      follow_up_scheduled_at = scheduled_at_value,
      follow_up_patient_seen_at = null,
      follow_up_patient_end_seen_at = null,
      follow_up_doctor_end_seen_at = null,
      updated_at = scheduled_at_value
  where id = b.id;

  -- Existing messages remain readable as a preview, but sending stays closed
  -- until the Pakistan calendar date reaches the scheduled follow-up day.
  update public.chat_rooms
  set is_active = false,
      updated_at = scheduled_at_value
  where booking_id = b.id;

  return jsonb_build_object(
    'booking_id', b.id,
    'patient_id', b.patient_id,
    'doctor_id', b.doctor_id,
    'follow_up_date', p_follow_up_date,
    'follow_up_scheduled_at', scheduled_at_value
  );
end;
$$;

revoke all on function public.schedule_consultation_follow_up(uuid, date)
  from public;
grant execute on function public.schedule_consultation_follow_up(uuid, date)
  to authenticated;

create or replace function public.end_consultation_follow_up(
  p_booking_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  ended_at_value timestamptz;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then
    raise exception 'Booking not found';
  end if;
  if auth.uid() <> b.doctor_id then
    raise exception 'Only the assigned doctor can end the follow-up';
  end if;
  if b.status <> 'completed' or b.follow_up_date is null then
    raise exception 'Follow-up not found';
  end if;
  if b.follow_up_date > local_today then
    raise exception 'The follow-up has not started yet';
  end if;

  if b.follow_up_ended_at is not null then
    return jsonb_build_object(
      'booking_id', b.id,
      'follow_up_ended_at', b.follow_up_ended_at
    );
  end if;

  ended_at_value := now();
  perform set_config('darman.follow_up_lifecycle_write', 'allowed', true);

  update public.bookings
  set follow_up_ended_at = ended_at_value,
      follow_up_ended_by = auth.uid(),
      follow_up_patient_end_seen_at = null,
      follow_up_doctor_end_seen_at = null,
      updated_at = ended_at_value
  where id = b.id;

  update public.chat_rooms
  set is_active = false,
      updated_at = ended_at_value
  where booking_id = b.id;

  return jsonb_build_object(
    'booking_id', b.id,
    'patient_id', b.patient_id,
    'doctor_id', b.doctor_id,
    'follow_up_ended_at', ended_at_value
  );
end;
$$;

revoke all on function public.end_consultation_follow_up(uuid) from public;
grant execute on function public.end_consultation_follow_up(uuid)
  to authenticated;

-- Correct rooms created by earlier follow-up migrations. The due-date RPCs
-- activate them again only after their server-checked date has arrived.
update public.chat_rooms as room
set is_active = false,
    updated_at = now()
from public.bookings as booking
where room.booking_id = booking.id
  and booking.status = 'completed'
  and booking.follow_up_date > (now() at time zone 'Asia/Karachi')::date
  and booking.follow_up_ended_at is null
  and room.is_active = true;

-- The app never updates chat rooms directly. Removing this grant prevents a
-- client from manually changing is_active to bypass the scheduled date.
revoke update, delete on public.chat_rooms from authenticated, anon;

-- PostgreSQL combines normal RLS policies with OR. A restrictive policy is
-- therefore required so an older permissive message policy cannot bypass the
-- follow-up date check merely because the user is a room participant.
drop policy if exists "Booking state gates all chat message inserts"
  on public.chat_messages;
create policy "Booking state gates all chat message inserts"
  on public.chat_messages
  as restrictive
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and exists (
      select 1
      from public.chat_rooms as room
      join public.bookings as booking on booking.id = room.booking_id
      where room.id = chat_messages.chat_room_id
        and booking.id = chat_messages.booking_id
        and room.is_active = true
        and auth.uid() in (booking.patient_id, booking.doctor_id)
        and (
          booking.status in ('pending', 'accepted', 'inProgress')
          or (
            booking.status = 'completed'
            and booking.follow_up_date is not null
            and booking.follow_up_date <=
              (now() at time zone 'Asia/Karachi')::date
            and booking.follow_up_ended_at is null
          )
        )
    )
  );

-- Generate a private server-to-server secret inside Vault. It is never placed
-- in the Flutter application or committed as plaintext.
do $$
declare
  secret_value text;
begin
  if not exists (
    select 1
    from vault.secrets
    where name = 'darman_follow_up_cron_secret'
  ) then
    secret_value := replace(gen_random_uuid()::text, '-', '')
      || replace(gen_random_uuid()::text, '-', '');
    perform vault.create_secret(
      secret_value,
      'darman_follow_up_cron_secret'
    );
  end if;
end;
$$;

create or replace function public.verify_follow_up_reminder_cron_secret(
  p_secret text
)
returns boolean
language sql
stable
security definer
set search_path = public, vault
as $$
  select coalesce(
    length(p_secret) >= 64
    and exists (
      select 1
      from vault.decrypted_secrets
      where name = 'darman_follow_up_cron_secret'
        and decrypted_secret = p_secret
    ),
    false
  );
$$;

revoke all on function public.verify_follow_up_reminder_cron_secret(text)
  from public;
grant execute on function public.verify_follow_up_reminder_cron_secret(text)
  to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'send-darman-follow-up-day-reminders';

-- 04:00 UTC is 09:00 in Pakistan. Hourly retries continue through the day,
-- now authenticated with both the project key and a private cron-only secret.
select cron.schedule(
  'send-darman-follow-up-day-reminders',
  '0 4-18 * * *',
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

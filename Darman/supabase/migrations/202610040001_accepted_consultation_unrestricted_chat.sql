begin;

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
  if new.type = 'system' then return new; end if;

  select * into booking from public.bookings where id = new.booking_id;
  if not found then return new; end if;

  -- The free tier applies only before a doctor accepts the request.
  if booking.status = 'pending'
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

create or replace function public.cancel_appointment_as_patient(
  p_booking_id uuid,
  p_reason text default 'Cancelled by patient'
) returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  patient_balance numeric;
  patient_reserved numeric;
begin
  select * into b from public.bookings where id = p_booking_id for update;
  if b.id is null then raise exception 'Appointment not found'; end if;
  if b.patient_id <> auth.uid() then raise exception 'Not authorized'; end if;
  if b.status <> 'pending' then
    raise exception 'Accepted consultations can only be cancelled by the doctor';
  end if;
  if clock_timestamp() < b.created_at + interval '30 minutes' then
    raise exception 'Cancellation is available 30 minutes after the request was created';
  end if;

  select coalesce(wallet_balance, 0), coalesce(wallet_reserved_balance, 0)
  into patient_balance, patient_reserved
  from public.users where uid = b.patient_id for update;

  update public.users
  set wallet_balance = patient_balance + b.consultation_fee,
      wallet_reserved_balance = greatest(patient_reserved - b.consultation_fee, 0),
      updated_at = now()
  where uid = b.patient_id;

  update public.bookings
  set status = 'cancelled', cancelled_by = auth.uid(),
      cancellation_reason = nullif(trim(p_reason), ''),
      cancelled_at = now(), updated_at = now()
  where id = b.id;
end;
$$;

revoke all on function public.cancel_appointment_as_patient(uuid, text) from public;
grant execute on function public.cancel_appointment_as_patient(uuid, text) to authenticated;

commit;

begin;

-- This also protects against two patients' acceptance actions racing on two
-- devices and placing the same patient in two consultations simultaneously.
create unique index if not exists one_in_progress_consultation_per_patient
  on public.bookings(patient_id)
  where status = 'inProgress';

create or replace function public.prevent_booking_during_active_consultation()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if exists (
    select 1
    from public.bookings
    where patient_id = new.patient_id
      and status = 'inProgress'
  ) then
    raise exception 'You already have an active consultation';
  end if;
  return new;
end;
$$;

drop trigger if exists prevent_booking_during_active_consultation
  on public.bookings;
create trigger prevent_booking_during_active_consultation
before insert on public.bookings
for each row
execute function public.prevent_booking_during_active_consultation();

create or replace function public.cancel_booking_as_doctor(
  p_booking_id uuid,
  p_reason text default 'Cancelled by doctor'
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  patient_balance numeric;
  patient_reserved numeric;
  refund_amount numeric;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then raise exception 'Appointment not found'; end if;
  if b.doctor_id <> auth.uid() then raise exception 'Not authorized'; end if;
  if b.status not in ('pending', 'accepted', 'inProgress') then
    raise exception 'This appointment can no longer be cancelled';
  end if;

  select coalesce(wallet_balance, 0), coalesce(wallet_reserved_balance, 0)
  into patient_balance, patient_reserved
  from public.users
  where uid = b.patient_id
  for update;

  refund_amount := round(coalesce(b.consultation_fee, 0)::numeric, 2);
  if refund_amount <= 0 then
    raise exception 'The consultation fee is invalid';
  end if;
  if patient_reserved < refund_amount then
    raise exception 'Reserved wallet funds are insufficient; cancellation was not completed';
  end if;

  update public.users
  set wallet_balance = patient_balance + refund_amount,
      wallet_reserved_balance = patient_reserved - refund_amount,
      updated_at = now()
  where uid = b.patient_id;

  update public.bookings
  set status = 'cancelled',
      cancelled_by = auth.uid(),
      cancellation_reason = nullif(trim(p_reason), ''),
      cancelled_at = now(),
      call_ended_at = case
        when b.status = 'inProgress' then now()
        else call_ended_at
      end,
      patient_left_at = case
        when b.status = 'inProgress' then now()
        else patient_left_at
      end,
      doctor_left_at = case
        when b.status = 'inProgress' then now()
        else doctor_left_at
      end,
      updated_at = now()
  where id = b.id;

  update public.consultation_call_invites
  set status = case
        when status = 'accepted' then 'ended'
        else 'cancelled'
      end,
      responded_at = coalesce(responded_at, now()),
      updated_at = now()
  where booking_id = b.id
    and status in ('ringing', 'accepted');

  update public.chat_rooms
  set is_active = false,
      updated_at = now()
  where booking_id = b.id;
end;
$$;

revoke all on function public.cancel_booking_as_doctor(uuid, text) from public;
grant execute on function public.cancel_booking_as_doctor(uuid, text)
  to authenticated;

commit;

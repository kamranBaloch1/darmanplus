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
begin
  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if b.id is null then raise exception 'Appointment not found'; end if;
  if b.doctor_id <> auth.uid() then raise exception 'Not authorized'; end if;
  if b.status not in ('pending', 'accepted') then
    raise exception 'This appointment can no longer be cancelled';
  end if;

  select coalesce(wallet_balance, 0), coalesce(wallet_reserved_balance, 0)
  into patient_balance, patient_reserved
  from public.users
  where uid = b.patient_id
  for update;

  update public.users
  set wallet_balance = patient_balance + b.consultation_fee,
      wallet_reserved_balance = greatest(patient_reserved - b.consultation_fee, 0),
      updated_at = now()
  where uid = b.patient_id;

  update public.bookings
  set status = 'cancelled',
      cancelled_by = auth.uid(),
      cancellation_reason = nullif(trim(p_reason), ''),
      cancelled_at = now(),
      updated_at = now()
  where id = b.id;
end;
$$;

revoke all on function public.cancel_booking_as_doctor(uuid, text) from public;
grant execute on function public.cancel_booking_as_doctor(uuid, text) to authenticated;

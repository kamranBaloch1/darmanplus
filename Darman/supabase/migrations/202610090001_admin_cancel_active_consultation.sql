begin;

alter table public.bookings
  add column if not exists admin_cancelled_by_email text;

create or replace function public.admin_cancel_active_consultation(
  p_booking_id uuid,
  p_reason text,
  p_admin_email text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  refund_amount numeric;
begin
  if nullif(btrim(p_admin_email), '') is null then
    raise exception 'Admin identity is required';
  end if;
  if char_length(btrim(coalesce(p_reason, ''))) not between 5 and 500 then
    raise exception 'A cancellation reason between 5 and 500 characters is required';
  end if;

  select * into b
  from public.bookings
  where id = p_booking_id
  for update;

  if not found then raise exception 'Consultation not found'; end if;
  if b.status not in ('accepted', 'inProgress') then
    raise exception 'Only active consultations can be cancelled';
  end if;

  refund_amount := round(coalesce(b.consultation_fee, 0)::numeric, 2);
  if refund_amount <= 0 then raise exception 'The consultation fee is invalid'; end if;

  perform 1 from public.users where uid = b.patient_id for update;
  if coalesce((select wallet_reserved_balance from public.users where uid = b.patient_id), 0) < refund_amount then
    raise exception 'Patient reserved funds are insufficient';
  end if;

  update public.users
  set wallet_balance = coalesce(wallet_balance, 0) + refund_amount,
      wallet_reserved_balance = coalesce(wallet_reserved_balance, 0) - refund_amount,
      updated_at = now()
  where uid = b.patient_id;

  update public.bookings
  set status = 'cancelled',
      cancelled_by = null,
      admin_cancelled_by_email = lower(btrim(p_admin_email)),
      cancellation_reason = btrim(p_reason),
      cancelled_at = now(),
      call_ended_at = coalesce(call_ended_at, now()),
      patient_left_at = coalesce(patient_left_at, now()),
      doctor_left_at = coalesce(doctor_left_at, now()),
      updated_at = now()
  where id = b.id;

  update public.consultation_call_invites
  set status = case when status = 'accepted' then 'ended' else 'cancelled' end,
      responded_at = coalesce(responded_at, now()),
      updated_at = now()
  where booking_id = b.id and status in ('ringing', 'accepted');

  update public.chat_rooms
  set is_active = false, updated_at = now()
  where booking_id = b.id;

  return jsonb_build_object(
    'booking_id', b.id,
    'patient_id', b.patient_id,
    'doctor_id', b.doctor_id,
    'patient_refund', refund_amount
  );
end;
$$;

revoke all on function public.admin_cancel_active_consultation(uuid, text, text) from public, anon, authenticated;
grant execute on function public.admin_cancel_active_consultation(uuid, text, text) to service_role;

commit;

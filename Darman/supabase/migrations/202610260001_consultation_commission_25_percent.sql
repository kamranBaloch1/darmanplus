begin;

create or replace function public.end_video_consultation(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  patient_balance numeric(12,2);
  patient_reserved numeric(12,2);
  doctor_balance numeric(12,2);
  gross numeric(12,2);
  commission numeric(12,2);
  earning numeric(12,2);
  platform_rate constant numeric(5,4) := 0.25;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if auth.uid() <> b.doctor_id then
    raise exception 'Only the assigned doctor can end the consultation';
  end if;

  -- Completed consultations retain the commission split recorded at completion.
  if b.status = 'completed' then
    return jsonb_build_object(
      'booking_id', b.id, 'gross_fee', b.gross_fee,
      'commission_rate', b.commission_rate,
      'commission_amount', b.commission_amount,
      'doctor_earning', b.doctor_earning,
      'completed_at', b.completed_at
    );
  end if;
  if b.status <> 'inProgress' then
    raise exception 'The consultation is not in progress';
  end if;

  perform 1 from public.users
  where uid in (b.patient_id, b.doctor_id)
  order by uid for update;

  select coalesce(wallet_balance, 0), coalesce(wallet_reserved_balance, 0)
    into patient_balance, patient_reserved
  from public.users where uid = b.patient_id;
  select coalesce(wallet_balance, 0)
    into doctor_balance
  from public.users where uid = b.doctor_id;

  gross := round(coalesce(b.consultation_fee, 0)::numeric, 2);
  if gross <= 0 then raise exception 'The consultation fee is invalid'; end if;
  if patient_reserved < gross then
    raise exception 'Reserved wallet funds are insufficient; settlement was not completed';
  end if;

  commission := round(gross * platform_rate, 2);
  earning := gross - commission;

  update public.users
  set wallet_reserved_balance = patient_reserved - gross
  where uid = b.patient_id;

  update public.users
  set wallet_balance = doctor_balance + earning
  where uid = b.doctor_id;

  update public.bookings set
    status = 'completed',
    completed_at = now(),
    call_ended_at = now(),
    gross_fee = gross,
    commission_rate = platform_rate,
    commission_amount = commission,
    doctor_earning = earning,
    updated_at = now()
  where id = b.id;

  insert into public.wallet_transactions (
    user_id, booking_id, transaction_type, amount, balance_after,
    reserved_balance_after, description, metadata
  ) values
  (
    b.patient_id, b.id, 'consultation_payment', -gross, patient_balance,
    patient_reserved - gross, 'Consultation payment completed',
    jsonb_build_object('doctor_id', b.doctor_id)
  ),
  (
    b.doctor_id, b.id, 'doctor_earning', earning, doctor_balance + earning,
    null, 'Consultation earning credited',
    jsonb_build_object(
      'gross_fee', gross,
      'commission', commission,
      'commission_rate', platform_rate
    )
  ),
  (
    null, b.id, 'platform_commission', commission, null,
    null, 'Platform commission collected',
    jsonb_build_object(
      'rate', platform_rate,
      'patient_id', b.patient_id,
      'doctor_id', b.doctor_id
    )
  );

  return jsonb_build_object(
    'booking_id', b.id, 'gross_fee', gross,
    'commission_rate', platform_rate,
    'commission_amount', commission,
    'doctor_earning', earning,
    'completed_at', now()
  );
end;
$$;

revoke all on function public.end_video_consultation(uuid) from public;
grant execute on function public.end_video_consultation(uuid) to authenticated;

commit;

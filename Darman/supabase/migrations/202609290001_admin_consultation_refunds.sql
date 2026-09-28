begin;

alter table public.bookings
  add column if not exists admin_refunded_at timestamptz,
  add column if not exists admin_refunded_by text,
  add column if not exists admin_refund_reason text;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_transaction_type_check;
alter table public.wallet_transactions
  add constraint wallet_transactions_transaction_type_check check (
    transaction_type in (
      'wallet_top_up', 'wallet_top_up_reversal', 'wallet_recovery',
      'consultation_payment', 'doctor_earning', 'platform_commission',
      'consultation_refund', 'doctor_refund_debit', 'platform_commission_refund'
    )
  );

create or replace function public.admin_refund_completed_consultation(
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
  patient_balance numeric(12,2);
  doctor_balance numeric(12,2);
  gross numeric(12,2);
  commission numeric(12,2);
  earning numeric(12,2);
  clean_reason text := trim(coalesce(p_reason, ''));
begin
  if auth.role() <> 'service_role' then
    raise exception 'Only the admin payment service can issue consultation refunds';
  end if;
  if length(clean_reason) < 5 or length(clean_reason) > 500 then
    raise exception 'Provide a refund reason between 5 and 500 characters';
  end if;

  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Consultation was not found'; end if;
  if b.status <> 'completed' then raise exception 'Only completed consultations can be refunded'; end if;
  if b.admin_refunded_at is not null then raise exception 'This consultation has already been refunded'; end if;

  gross := round(coalesce(b.gross_fee, b.consultation_fee, 0)::numeric, 2);
  commission := round(coalesce(b.commission_amount, gross * coalesce(b.commission_rate, 0.12))::numeric, 2);
  earning := round(coalesce(b.doctor_earning, gross - commission)::numeric, 2);
  if gross <= 0 or earning < 0 or commission < 0 or earning + commission <> gross then
    raise exception 'The consultation settlement values are invalid';
  end if;

  perform 1 from public.users
  where uid in (b.patient_id, b.doctor_id)
  order by uid for update;
  select coalesce(wallet_balance, 0) into patient_balance from public.users where uid = b.patient_id;
  select coalesce(wallet_balance, 0) into doctor_balance from public.users where uid = b.doctor_id;
  if patient_balance is null or doctor_balance is null then raise exception 'Patient or doctor wallet was not found'; end if;
  if doctor_balance < earning then
    raise exception 'The doctor wallet has insufficient funds for this refund';
  end if;

  update public.users set wallet_balance = patient_balance + gross where uid = b.patient_id;
  update public.users set wallet_balance = doctor_balance - earning where uid = b.doctor_id;

  insert into public.wallet_transactions (
    user_id, booking_id, transaction_type, amount, balance_after,
    description, metadata
  ) values
  (b.patient_id, b.id, 'consultation_refund', gross, patient_balance + gross,
   'Consultation payment refunded by Darman',
   jsonb_build_object('doctor_id', b.doctor_id, 'reason', clean_reason, 'admin_email', p_admin_email)),
  (b.doctor_id, b.id, 'doctor_refund_debit', -earning, doctor_balance - earning,
   'Consultation earning reversed by Darman',
   jsonb_build_object('patient_id', b.patient_id, 'gross_fee', gross, 'reason', clean_reason, 'admin_email', p_admin_email)),
  (null, b.id, 'platform_commission_refund', -commission, null,
   'Platform commission reversed for consultation refund',
   jsonb_build_object('patient_id', b.patient_id, 'doctor_id', b.doctor_id, 'reason', clean_reason, 'admin_email', p_admin_email));

  update public.bookings set
    admin_refunded_at = now(), admin_refunded_by = lower(trim(p_admin_email)),
    admin_refund_reason = clean_reason, updated_at = now()
  where id = b.id;

  return jsonb_build_object(
    'booking_id', b.id, 'patient_id', b.patient_id, 'doctor_id', b.doctor_id,
    'patient_refund', gross, 'doctor_debit', earning,
    'commission_reversal', commission, 'refunded_at', now()
  );
end;
$$;

revoke all on function public.admin_refund_completed_consultation(uuid, text, text) from public, anon, authenticated;
grant execute on function public.admin_refund_completed_consultation(uuid, text, text) to service_role;

commit;

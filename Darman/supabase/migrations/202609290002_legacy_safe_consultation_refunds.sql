begin;

-- Older mobile releases throw when they receive a transaction type added
-- after that release. Keep user-facing refund rows on legacy-safe types and
-- retain their real meaning in metadata for newer releases and admin audit.
create or replace function public.make_consultation_refunds_legacy_safe()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.transaction_type = 'consultation_refund' then
    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
      'ledger_kind', 'consultation_refund',
      'refund_booking_id', new.booking_id
    );
    new.transaction_type := 'wallet_top_up';
    new.booking_id := null;
  elsif new.transaction_type = 'doctor_refund_debit' then
    new.metadata := coalesce(new.metadata, '{}'::jsonb) || jsonb_build_object(
      'ledger_kind', 'doctor_refund_debit',
      'refund_booking_id', new.booking_id
    );
    new.transaction_type := 'wallet_top_up_reversal';
    new.booking_id := null;
  end if;
  return new;
end;
$$;

drop trigger if exists make_consultation_refunds_legacy_safe on public.wallet_transactions;
create trigger make_consultation_refunds_legacy_safe
before insert on public.wallet_transactions
for each row execute function public.make_consultation_refunds_legacy_safe();

update public.wallet_transactions
set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'ledger_kind', 'consultation_refund',
      'refund_booking_id', booking_id
    ),
    transaction_type = 'wallet_top_up',
    booking_id = null
where transaction_type = 'consultation_refund';

update public.wallet_transactions
set metadata = coalesce(metadata, '{}'::jsonb) || jsonb_build_object(
      'ledger_kind', 'doctor_refund_debit',
      'refund_booking_id', booking_id
    ),
    transaction_type = 'wallet_top_up_reversal',
    booking_id = null
where transaction_type = 'doctor_refund_debit';

commit;

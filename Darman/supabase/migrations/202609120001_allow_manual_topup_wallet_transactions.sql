begin;

alter table public.wallet_transactions
  alter column booking_id drop not null;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_check;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_booking_shape_check;

alter table public.wallet_transactions
  add constraint wallet_transactions_booking_shape_check check (
    (
      transaction_type in ('wallet_top_up', 'wallet_top_up_reversal', 'wallet_recovery')
      and booking_id is null
      and user_id is not null
    )
    or
    (
      transaction_type not in ('wallet_top_up', 'wallet_top_up_reversal', 'wallet_recovery')
      and booking_id is not null
    )
  );

commit;

begin;

-- A reversed provider payment must never silently become platform credit. Keep
-- the spendable balance non-negative and track any unrecovered amount as debt.
alter table public.users
  add column if not exists wallet_recovery_due numeric(12,2) not null default 0;

alter table public.users
  drop constraint if exists users_wallet_recovery_due_check;
alter table public.users
  add constraint users_wallet_recovery_due_check
  check (wallet_recovery_due >= 0);

-- Only service-role requests and SECURITY DEFINER database functions may
-- mutate balances. Profile updates from a mobile client can no longer forge a
-- wallet balance.
create or replace function public.protect_wallet_balances()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if tg_op = 'INSERT'
     and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    new.wallet_balance := 0;
    new.wallet_reserved_balance := 0;
    new.wallet_recovery_due := 0;
  elsif tg_op = 'UPDATE'
     and current_user not in ('postgres', 'service_role', 'supabase_admin') then
    raise exception 'Wallet balances can only be changed by the payment service';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_wallet_balances on public.users;
create trigger protect_wallet_balances
before insert or update of wallet_balance, wallet_reserved_balance, wallet_recovery_due
on public.users
for each row execute function public.protect_wallet_balances();

-- Reversals are separate immutable ledger entries linked to the original
-- credit. Recovery payments record future deposits used to clear wallet debt.
alter table public.wallet_transactions
  add column if not exists reversal_of_transaction_id uuid
    references public.wallet_transactions(id) on delete restrict;

create unique index if not exists wallet_transactions_one_reversal_per_credit
  on public.wallet_transactions(reversal_of_transaction_id)
  where reversal_of_transaction_id is not null;

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_transaction_type_check;
alter table public.wallet_transactions
  add constraint wallet_transactions_transaction_type_check check (
    transaction_type in (
      'wallet_top_up',
      'wallet_top_up_reversal',
      'wallet_recovery',
      'consultation_payment',
      'doctor_earning',
      'platform_commission'
    )
  );

alter table public.wallet_transactions
  drop constraint if exists wallet_transactions_check;
alter table public.wallet_transactions
  add constraint wallet_transactions_booking_shape_check check (
    (
      transaction_type in (
        'wallet_top_up', 'wallet_top_up_reversal', 'wallet_recovery'
      )
      and booking_id is null
      and user_id is not null
    )
    or
    (
      transaction_type not in (
        'wallet_top_up', 'wallet_top_up_reversal', 'wallet_recovery'
      )
      and booking_id is not null
    )
  );

alter table public.wallet_top_up_requests
  drop constraint if exists wallet_top_up_requests_status_check;
alter table public.wallet_top_up_requests
  add constraint wallet_top_up_requests_status_check check (
    status in ('pending', 'succeeded', 'failed', 'expired', 'reversed')
  );

alter table public.wallet_top_up_requests
  add column if not exists settlement_status text not null default 'not_applicable',
  add column if not exists settlement_date date,
  add column if not exists settled_at timestamptz,
  add column if not exists reversed_at timestamptz,
  add column if not exists last_reconciled_at timestamptz,
  add column if not exists next_reconciliation_at timestamptz,
  add column if not exists reconciliation_attempts integer not null default 0,
  add column if not exists reversal_transaction_id uuid
    references public.wallet_transactions(id) on delete restrict;

alter table public.wallet_top_up_requests
  drop constraint if exists wallet_top_up_requests_settlement_status_check;
alter table public.wallet_top_up_requests
  add constraint wallet_top_up_requests_settlement_status_check check (
    settlement_status in (
      'not_applicable', 'awaiting_settlement', 'settled',
      'reversed', 'review_required'
    )
  );

create unique index if not exists wallet_top_up_requests_reversal_unique
  on public.wallet_top_up_requests(reversal_transaction_id)
  where reversal_transaction_id is not null;

create index if not exists wallet_top_up_requests_reconciliation_due_idx
  on public.wallet_top_up_requests(next_reconciliation_at)
  where status = 'succeeded'
    and settlement_status in ('awaiting_settlement', 'review_required');

update public.wallet_top_up_requests
set settlement_status = 'awaiting_settlement',
    next_reconciliation_at = coalesce(next_reconciliation_at, now())
where status = 'succeeded'
  and settlement_status = 'not_applicable';

-- Replace the callback finalizer so future top-ups first clear any amount owed
-- because of a previous provider reversal, then credit the remaining balance.
create or replace function public.finalize_jazzcash_wallet_top_up(
  p_merchant_txn_ref text,
  p_amount_minor bigint,
  p_response_code text,
  p_response_message text,
  p_provider_reference text,
  p_response_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.wallet_top_up_requests%rowtype;
  current_balance numeric(12,2);
  current_recovery_due numeric(12,2);
  recovery_applied numeric(12,2);
  spendable_credit numeric(12,2);
  new_balance numeric(12,2);
  remaining_recovery_due numeric(12,2);
  transaction_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  select * into request_row
  from public.wallet_top_up_requests
  where merchant_txn_ref = p_merchant_txn_ref
  for update;

  if not found then raise exception 'Top-up request not found'; end if;
  if request_row.amount_minor <> p_amount_minor then
    raise exception 'Payment amount does not match the top-up request';
  end if;

  if request_row.status in ('succeeded', 'reversed') then
    return jsonb_build_object(
      'request_id', request_row.id,
      'status', request_row.status,
      'wallet_transaction_id', request_row.wallet_transaction_id
    );
  end if;

  if p_response_code = '000' then
    select coalesce(wallet_balance, 0), coalesce(wallet_recovery_due, 0)
    into current_balance, current_recovery_due
    from public.users
    where uid = request_row.user_id
    for update;

    if not found then raise exception 'Patient account not found'; end if;

    recovery_applied := least(current_recovery_due, request_row.amount);
    spendable_credit := request_row.amount - recovery_applied;
    new_balance := round(current_balance + spendable_credit, 2);
    remaining_recovery_due := round(current_recovery_due - recovery_applied, 2);

    update public.users
    set wallet_balance = new_balance,
        wallet_recovery_due = remaining_recovery_due,
        updated_at = now()
    where uid = request_row.user_id;

    insert into public.wallet_transactions (
      user_id, booking_id, top_up_request_id, transaction_type, currency,
      amount, balance_after, reserved_balance_after, description, metadata
    ) values (
      request_row.user_id, null, request_row.id, 'wallet_top_up', 'PKR',
      request_row.amount, new_balance, null, 'Wallet top-up via JazzCash',
      jsonb_build_object(
        'provider', 'jazzcash',
        'merchant_txn_ref', request_row.merchant_txn_ref,
        'provider_reference', nullif(p_provider_reference, ''),
        'spendable_credit', spendable_credit,
        'recovery_applied', recovery_applied
      )
    ) returning id into transaction_id;

    if recovery_applied > 0 then
      insert into public.wallet_transactions (
        user_id, booking_id, transaction_type, currency, amount,
        balance_after, reserved_balance_after, description, metadata
      ) values (
        request_row.user_id, null, 'wallet_recovery', 'PKR', -recovery_applied,
        new_balance, null, 'Recovered a reversed JazzCash payment',
        jsonb_build_object(
          'top_up_request_id', request_row.id,
          'merchant_txn_ref', request_row.merchant_txn_ref,
          'remaining_recovery_due', remaining_recovery_due
        )
      );
    end if;

    update public.wallet_top_up_requests
    set status = 'succeeded',
        settlement_status = 'awaiting_settlement',
        next_reconciliation_at = now() + interval '1 hour',
        provider_reference = nullif(p_provider_reference, ''),
        response_code = p_response_code,
        response_message = left(coalesce(p_response_message, ''), 500),
        response_payload = coalesce(p_response_payload, '{}'::jsonb),
        wallet_transaction_id = transaction_id,
        completed_at = now(),
        updated_at = now()
    where id = request_row.id;
  else
    update public.wallet_top_up_requests
    set status = 'failed',
        settlement_status = 'not_applicable',
        provider_reference = nullif(p_provider_reference, ''),
        response_code = left(coalesce(p_response_code, ''), 20),
        response_message = left(coalesce(p_response_message, 'Payment failed'), 500),
        response_payload = coalesce(p_response_payload, '{}'::jsonb),
        updated_at = now()
    where id = request_row.id;
  end if;

  return jsonb_build_object(
    'request_id', request_row.id,
    'status', case when p_response_code = '000' then 'succeeded' else 'failed' end,
    'wallet_transaction_id', transaction_id
  );
end;
$$;

create or replace function public.get_my_wallet_top_up_status(
  p_request_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.wallet_top_up_requests%rowtype;
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  update public.wallet_top_up_requests
  set status = 'expired',
      response_message = coalesce(response_message, 'Payment session expired'),
      updated_at = now()
  where id = p_request_id
    and user_id = auth.uid()
    and status = 'pending'
    and expires_at < now();

  select * into request_row
  from public.wallet_top_up_requests
  where id = p_request_id and user_id = auth.uid();
  if not found then raise exception 'Top-up request not found'; end if;

  return jsonb_build_object(
    'request_id', request_row.id,
    'amount', request_row.amount,
    'currency', request_row.currency,
    'status', request_row.status,
    'settlement_status', request_row.settlement_status,
    'response_code', request_row.response_code,
    'response_message', request_row.response_message,
    'provider_reference', request_row.provider_reference,
    'wallet_transaction_id', request_row.wallet_transaction_id,
    'expires_at', request_row.expires_at,
    'completed_at', request_row.completed_at,
    'reversed_at', request_row.reversed_at
  );
end;
$$;

-- Atomically reserve consultation money on the server. The client can no
-- longer edit balances or create a booking in two separate race-prone steps.
create or replace function public.create_patient_booking_secure(
  p_doctor_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  current_patient_id uuid := auth.uid();
  patient_role text;
  doctor_role text;
  doctor_available boolean;
  fee numeric(12,2);
  patient_balance numeric(12,2);
  patient_reserved numeric(12,2);
  recovery_due numeric(12,2);
  booking_row public.bookings%rowtype;
begin
  if current_patient_id is null then raise exception 'Authentication required'; end if;
  if p_doctor_id is null or p_doctor_id = current_patient_id then
    raise exception 'You cannot book yourself';
  end if;

  perform 1 from public.users
  where uid in (current_patient_id, p_doctor_id)
  order by uid
  for update;

  select role, coalesce(wallet_balance, 0),
         coalesce(wallet_reserved_balance, 0), coalesce(wallet_recovery_due, 0)
  into patient_role, patient_balance, patient_reserved, recovery_due
  from public.users where uid = current_patient_id;
  if not found or patient_role <> 'patient' then
    raise exception 'Only patient accounts can book consultations';
  end if;

  select role, coalesce(is_available, false), consultation_fee
  into doctor_role, doctor_available, fee
  from public.users where uid = p_doctor_id;
  if not found or doctor_role <> 'doctor' then
    raise exception 'This doctor could not be found';
  end if;
  if not doctor_available then raise exception 'This doctor is not available right now'; end if;
  if fee is null or fee <= 0 then
    raise exception 'This doctor has not set a consultation fee yet';
  end if;
  if recovery_due > 0 then
    raise exception 'Your wallet has a reversed payment. Add money to clear it before booking';
  end if;
  if patient_balance < fee then
    raise exception 'Insufficient wallet balance';
  end if;

  if exists (
    select 1 from public.bookings
    where patient_id = current_patient_id
      and doctor_id = p_doctor_id
      and status in ('pending', 'accepted', 'inProgress')
  ) then
    raise exception 'You already have an active booking with this doctor';
  end if;

  update public.users
  set wallet_balance = round(patient_balance - fee, 2),
      wallet_reserved_balance = round(patient_reserved + fee, 2),
      updated_at = now()
  where uid = current_patient_id;

  insert into public.bookings (
    patient_id, doctor_id, status, consultation_fee, created_at, updated_at
  ) values (
    current_patient_id, p_doctor_id, 'pending', fee, now(), now()
  ) returning * into booking_row;

  return to_jsonb(booking_row);
end;
$$;

revoke all on function public.create_patient_booking_secure(uuid) from public;
grant execute on function public.create_patient_booking_secure(uuid) to authenticated;

-- The worker claims a bounded batch so concurrent cron invocations cannot
-- reconcile the same payment at the same time.
create or replace function public.claim_jazzcash_top_ups_for_reconciliation(
  p_limit integer default 25
)
returns table (
  request_id uuid,
  merchant_txn_ref text,
  amount_minor bigint,
  provider_reference text,
  created_at timestamptz,
  reconciliation_attempts integer
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_limit < 1 or p_limit > 100 then raise exception 'Invalid batch size'; end if;

  return query
  with due as (
    select request.id
    from public.wallet_top_up_requests request
    where request.status = 'succeeded'
      and request.settlement_status in ('awaiting_settlement', 'review_required')
      and coalesce(request.next_reconciliation_at, now()) <= now()
    order by request.next_reconciliation_at nulls first, request.created_at
    for update skip locked
    limit p_limit
  )
  update public.wallet_top_up_requests request
  set reconciliation_attempts = request.reconciliation_attempts + 1,
      last_reconciled_at = now(),
      next_reconciliation_at = now() + interval '6 hours',
      updated_at = now()
  from due
  where request.id = due.id
  returning request.id, request.merchant_txn_ref, request.amount_minor,
            request.provider_reference, request.created_at,
            request.reconciliation_attempts;
end;
$$;

create or replace function public.apply_jazzcash_reconciliation_result(
  p_request_id uuid,
  p_state text,
  p_provider_status text,
  p_provider_reference text default null,
  p_settlement_date date default null,
  p_response_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.wallet_top_up_requests%rowtype;
  current_balance numeric(12,2);
  current_recovery_due numeric(12,2);
  recovered_now numeric(12,2);
  recovery_shortfall numeric(12,2);
  new_balance numeric(12,2);
  new_recovery_due numeric(12,2);
  reversal_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;
  if p_state not in ('pending', 'settled', 'reversed', 'review_required') then
    raise exception 'Invalid reconciliation state';
  end if;

  select * into request_row
  from public.wallet_top_up_requests
  where id = p_request_id
  for update;
  if not found then raise exception 'Top-up request not found'; end if;
  if request_row.status not in ('succeeded', 'reversed') then
    raise exception 'Only successful top-ups can be reconciled';
  end if;

  if request_row.status = 'reversed' then
    return jsonb_build_object(
      'request_id', request_row.id,
      'status', 'reversed',
      'reversal_transaction_id', request_row.reversal_transaction_id
    );
  end if;

  if p_state = 'reversed' then
    select coalesce(wallet_balance, 0), coalesce(wallet_recovery_due, 0)
    into current_balance, current_recovery_due
    from public.users where uid = request_row.user_id for update;
    if not found then raise exception 'Patient account not found'; end if;

    recovered_now := least(current_balance, request_row.amount);
    recovery_shortfall := request_row.amount - recovered_now;
    new_balance := round(current_balance - recovered_now, 2);
    new_recovery_due := round(current_recovery_due + recovery_shortfall, 2);

    update public.users
    set wallet_balance = new_balance,
        wallet_recovery_due = new_recovery_due,
        updated_at = now()
    where uid = request_row.user_id;

    insert into public.wallet_transactions (
      user_id, booking_id, transaction_type, currency, amount, balance_after,
      reserved_balance_after, description, metadata,
      reversal_of_transaction_id
    ) values (
      request_row.user_id, null, 'wallet_top_up_reversal', 'PKR',
      -request_row.amount, new_balance, null,
      'JazzCash payment reversed',
      jsonb_build_object(
        'provider', 'jazzcash',
        'merchant_txn_ref', request_row.merchant_txn_ref,
        'provider_status', left(coalesce(p_provider_status, ''), 100),
        'recovered_from_balance', recovered_now,
        'recovery_due', new_recovery_due
      ),
      request_row.wallet_transaction_id
    ) returning id into reversal_id;

    update public.wallet_top_up_requests
    set status = 'reversed',
        settlement_status = 'reversed',
        reversed_at = now(),
        reversal_transaction_id = reversal_id,
        provider_reference = coalesce(nullif(p_provider_reference, ''), provider_reference),
        settlement_date = coalesce(p_settlement_date, settlement_date),
        response_payload = response_payload || jsonb_build_object(
          'last_reconciliation', coalesce(p_response_payload, '{}'::jsonb)
        ),
        next_reconciliation_at = null,
        updated_at = now()
    where id = request_row.id;
  elsif p_state = 'settled' then
    update public.wallet_top_up_requests
    set settlement_status = 'settled',
        settlement_date = coalesce(p_settlement_date, settlement_date),
        settled_at = now(),
        provider_reference = coalesce(nullif(p_provider_reference, ''), provider_reference),
        response_payload = response_payload || jsonb_build_object(
          'last_reconciliation', coalesce(p_response_payload, '{}'::jsonb)
        ),
        next_reconciliation_at = null,
        updated_at = now()
    where id = request_row.id;
  else
    update public.wallet_top_up_requests
    set settlement_status = case
          when p_state = 'review_required' then 'review_required'
          else 'awaiting_settlement'
        end,
        settlement_date = coalesce(p_settlement_date, settlement_date),
        provider_reference = coalesce(nullif(p_provider_reference, ''), provider_reference),
        response_payload = response_payload || jsonb_build_object(
          'last_reconciliation', coalesce(p_response_payload, '{}'::jsonb)
        ),
        next_reconciliation_at = now() + case
          when p_state = 'review_required' then interval '24 hours'
          else interval '6 hours'
        end,
        updated_at = now()
    where id = request_row.id;
  end if;

  return jsonb_build_object(
    'request_id', request_row.id,
    'status', case when p_state = 'reversed' then 'reversed' else 'succeeded' end,
    'settlement_status', p_state,
    'reversal_transaction_id', reversal_id
  );
end;
$$;

revoke all on function public.claim_jazzcash_top_ups_for_reconciliation(integer)
  from public;
revoke all on function public.apply_jazzcash_reconciliation_result(
  uuid, text, text, text, date, jsonb
) from public;
grant execute on function public.claim_jazzcash_top_ups_for_reconciliation(integer)
  to service_role;
grant execute on function public.apply_jazzcash_reconciliation_result(
  uuid, text, text, text, date, jsonb
) to service_role;

-- A private cron secret authenticates the scheduled Edge Function without
-- exposing any service key in SQL or in the mobile application.
do $$
declare
  secret_value text;
begin
  if not exists (
    select 1 from vault.secrets
    where name = 'darman_wallet_reconciliation_cron_secret'
  ) then
    secret_value := replace(gen_random_uuid()::text, '-', '')
      || replace(gen_random_uuid()::text, '-', '');
    perform vault.create_secret(
      secret_value,
      'darman_wallet_reconciliation_cron_secret'
    );
  end if;
end;
$$;

create or replace function public.verify_wallet_reconciliation_cron_secret(
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
      select 1 from vault.decrypted_secrets
      where name = 'darman_wallet_reconciliation_cron_secret'
        and decrypted_secret = p_secret
    ),
    false
  );
$$;

revoke all on function public.verify_wallet_reconciliation_cron_secret(text)
  from public;
grant execute on function public.verify_wallet_reconciliation_cron_secret(text)
  to service_role;

select cron.unschedule(jobid)
from cron.job
where jobname = 'reconcile-darman-jazzcash-wallet-top-ups';

select cron.schedule(
  'reconcile-darman-jazzcash-wallet-top-ups',
  '17 */6 * * *',
  $cron$
    select net.http_post(
      url := (
        select decrypted_secret from vault.decrypted_secrets
        where name = 'darman_follow_up_project_url'
      ) || '/functions/v1/reconcile-jazzcash-wallet-top-ups',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'apikey', (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'darman_follow_up_publishable_key'
        ),
        'x-darman-cron-secret', (
          select decrypted_secret from vault.decrypted_secrets
          where name = 'darman_wallet_reconciliation_cron_secret'
        )
      ),
      body := jsonb_build_object('scheduled_at', now()),
      timeout_milliseconds := 30000
    ) as request_id;
  $cron$
);

commit;

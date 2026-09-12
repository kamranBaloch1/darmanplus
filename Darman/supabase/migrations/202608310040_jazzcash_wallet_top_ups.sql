begin;

create table if not exists public.wallet_top_up_requests (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(uid) on delete restrict,
  provider text not null default 'jazzcash' check (provider = 'jazzcash'),
  amount numeric(12,2) not null check (amount > 0),
  amount_minor bigint not null check (amount_minor > 0),
  currency text not null default 'PKR' check (currency = 'PKR'),
  status text not null default 'pending' check (
    status in ('pending', 'succeeded', 'failed', 'expired')
  ),
  merchant_txn_ref text not null unique,
  checkout_token_hash text not null unique,
  provider_reference text,
  response_code text,
  response_message text,
  response_payload jsonb not null default '{}'::jsonb,
  wallet_transaction_id uuid,
  expires_at timestamptz not null,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (amount_minor = round(amount * 100)::bigint)
);

create index if not exists wallet_top_up_requests_user_created_idx
  on public.wallet_top_up_requests(user_id, created_at desc);
create index if not exists wallet_top_up_requests_pending_expiry_idx
  on public.wallet_top_up_requests(expires_at)
  where status = 'pending';

alter table public.wallet_top_up_requests enable row level security;
revoke all on public.wallet_top_up_requests from anon, authenticated;

alter table public.wallet_transactions
  add column if not exists top_up_request_id uuid
    references public.wallet_top_up_requests(id) on delete restrict;

create unique index if not exists wallet_transactions_top_up_request_unique
  on public.wallet_transactions(top_up_request_id)
  where top_up_request_id is not null;

alter table public.wallet_top_up_requests
  drop constraint if exists wallet_top_up_requests_wallet_transaction_fk;
alter table public.wallet_top_up_requests
  add constraint wallet_top_up_requests_wallet_transaction_fk
  foreign key (wallet_transaction_id)
  references public.wallet_transactions(id)
  on delete restrict;

create or replace function public.create_wallet_top_up_request(
  p_amount numeric,
  p_checkout_token_hash text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  request_row public.wallet_top_up_requests%rowtype;
  user_role text;
  normalized_amount numeric(12,2);
  transaction_ref text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select role into user_role
  from public.users
  where uid = auth.uid();

  if not found or user_role <> 'patient' then
    raise exception 'Only patient accounts can add money';
  end if;

  if p_amount is null or p_amount <> trunc(p_amount) then
    raise exception 'Enter a whole-number amount in PKR';
  end if;

  normalized_amount := round(p_amount, 2);
  if normalized_amount < 100 or normalized_amount > 1000000 then
    raise exception 'Amount must be between Rs. 100 and Rs. 1,000,000';
  end if;

  if p_checkout_token_hash is null
     or p_checkout_token_hash !~ '^[0-9a-f]{64}$' then
    raise exception 'Invalid checkout token';
  end if;

  update public.wallet_top_up_requests
  set status = 'expired',
      response_message = coalesce(response_message, 'Payment session expired'),
      updated_at = now()
  where user_id = auth.uid()
    and status = 'pending'
    and expires_at < now();

  if (
    select count(*) >= 3
    from public.wallet_top_up_requests
    where user_id = auth.uid()
      and status = 'pending'
      and created_at > now() - interval '30 minutes'
  ) then
    raise exception 'You already have pending JazzCash payments. Complete one or wait for it to expire';
  end if;

  transaction_ref := 'T'
    || to_char(clock_timestamp() at time zone 'Asia/Karachi', 'YYYYMMDDHH24MISS')
    || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 5));

  insert into public.wallet_top_up_requests (
    user_id,
    amount,
    amount_minor,
    merchant_txn_ref,
    checkout_token_hash,
    expires_at
  ) values (
    auth.uid(),
    normalized_amount,
    round(normalized_amount * 100)::bigint,
    transaction_ref,
    p_checkout_token_hash,
    now() + interval '30 minutes'
  )
  returning * into request_row;

  return jsonb_build_object(
    'request_id', request_row.id,
    'merchant_txn_ref', request_row.merchant_txn_ref,
    'amount', request_row.amount,
    'currency', request_row.currency,
    'status', request_row.status,
    'expires_at', request_row.expires_at
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
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

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
  where id = p_request_id
    and user_id = auth.uid();

  if not found then
    raise exception 'Top-up request not found';
  end if;

  return jsonb_build_object(
    'request_id', request_row.id,
    'amount', request_row.amount,
    'currency', request_row.currency,
    'status', request_row.status,
    'response_code', request_row.response_code,
    'response_message', request_row.response_message,
    'provider_reference', request_row.provider_reference,
    'wallet_transaction_id', request_row.wallet_transaction_id,
    'expires_at', request_row.expires_at,
    'completed_at', request_row.completed_at
  );
end;
$$;

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
  new_balance numeric(12,2);
  transaction_id uuid;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'Service role required';
  end if;

  select * into request_row
  from public.wallet_top_up_requests
  where merchant_txn_ref = p_merchant_txn_ref
  for update;

  if not found then
    raise exception 'Top-up request not found';
  end if;
  if request_row.amount_minor <> p_amount_minor then
    raise exception 'Payment amount does not match the top-up request';
  end if;

  if request_row.status = 'succeeded' then
    return jsonb_build_object(
      'request_id', request_row.id,
      'status', request_row.status,
      'wallet_transaction_id', request_row.wallet_transaction_id
    );
  end if;

  if p_response_code = '000' then
    select coalesce(wallet_balance, 0)
    into current_balance
    from public.users
    where uid = request_row.user_id
    for update;

    if not found then
      raise exception 'Patient account not found';
    end if;

    new_balance := round(current_balance + request_row.amount, 2);
    update public.users
    set wallet_balance = new_balance,
        updated_at = now()
    where uid = request_row.user_id;

    insert into public.wallet_transactions (
      user_id,
      booking_id,
      top_up_request_id,
      transaction_type,
      currency,
      amount,
      balance_after,
      reserved_balance_after,
      description,
      metadata
    ) values (
      request_row.user_id,
      null,
      request_row.id,
      'wallet_top_up',
      'PKR',
      request_row.amount,
      new_balance,
      null,
      'Wallet top-up via JazzCash',
      jsonb_build_object(
        'provider', 'jazzcash',
        'merchant_txn_ref', request_row.merchant_txn_ref,
        'provider_reference', nullif(p_provider_reference, '')
      )
    )
    returning id into transaction_id;

    update public.wallet_top_up_requests
    set status = 'succeeded',
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

revoke all on function public.create_wallet_top_up_request(numeric, text)
  from public;
revoke all on function public.get_my_wallet_top_up_status(uuid)
  from public;
revoke all on function public.finalize_jazzcash_wallet_top_up(
  text, bigint, text, text, text, jsonb
) from public;

grant execute on function public.create_wallet_top_up_request(numeric, text)
  to authenticated;
grant execute on function public.get_my_wallet_top_up_status(uuid)
  to authenticated;
grant execute on function public.finalize_jazzcash_wallet_top_up(
  text, bigint, text, text, text, jsonb
) to service_role;

commit;

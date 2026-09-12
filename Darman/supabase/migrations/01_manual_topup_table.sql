-- Darman: manual JazzCash top-up requests
-- Updated: amount is determined by the team from the receipt.
-- Run in Supabase SQL Editor.

create table if not exists public.wallet_top_up_requests (

  id uuid primary key default gen_random_uuid(),

  user_id uuid not null
    references auth.users(id)
    on delete cascade,

  -- Amount is NULL until the team verifies the receipt.
  amount bigint
    check (amount is null or (amount >= 100 and amount <= 1000000)),

  currency text not null default 'PKR',

  payment_method text not null default 'jazzcash_manual',

  -- User uploads a screenshot/receipt.
  receipt_url text,

  status text not null default 'submitted'
    check (
      status in ('submitted', 'verified', 'rejected', 'expired')
    ),

  created_at timestamptz not null default now(),

  submitted_at timestamptz not null default now(),

  verified_at timestamptz,

  verified_by uuid
    references auth.users(id),

  rejection_reason text
);


-- ============================================================
-- INDEXES
-- ============================================================

create index if not exists wallet_top_up_requests_user_idx
  on public.wallet_top_up_requests(user_id, created_at desc);

create index if not exists wallet_top_up_requests_status_idx
  on public.wallet_top_up_requests(status, created_at desc);


-- ============================================================
-- ROW LEVEL SECURITY
-- ============================================================

alter table public.wallet_top_up_requests
enable row level security;


drop policy if exists "Users can view own topups"
on public.wallet_top_up_requests;

create policy "Users can view own topups"
on public.wallet_top_up_requests
for select
to authenticated
using (
  user_id = auth.uid()
);


-- Users must NOT directly insert/update/delete top-up records.
-- Creation and verification should happen through secure RPCs.

revoke insert, update, delete
on public.wallet_top_up_requests
from authenticated;


-- ============================================================
-- MANUAL TOP-UP CREATION RPC
-- ============================================================
-- User only submits the receipt.
-- Amount is intentionally NULL.
-- The team determines the amount from the receipt later.

create or replace function public.create_manual_wallet_top_up(
  p_receipt_url text
)
returns public.wallet_top_up_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_row public.wallet_top_up_requests;
begin

  if auth.uid() is null then
    raise exception 'Not authenticated';
  end if;

  if p_receipt_url is null
     or length(trim(p_receipt_url)) = 0 then
    raise exception 'Payment receipt is required';
  end if;

  insert into public.wallet_top_up_requests (
    user_id,
    amount,
    currency,
    payment_method,
    receipt_url,
    status,
    submitted_at
  )
  values (
    auth.uid(),
    null,
    'PKR',
    'jazzcash_manual',
    trim(p_receipt_url),
    'submitted',
    now()
  )
  returning *
  into v_row;

  return v_row;

end;
$$;


-- ============================================================
-- RPC SECURITY
-- ============================================================

revoke all
on function public.create_manual_wallet_top_up(text)
from public;

grant execute
on function public.create_manual_wallet_top_up(text)
to authenticated;
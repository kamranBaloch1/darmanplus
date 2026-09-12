-- ADMIN VERIFICATION
--
-- IMPORTANT:
-- The wallet_transactions columns differ between projects.
-- Replace ONLY the marked INSERT with your existing ledger INSERT.
--
-- The critical property is that the wallet update + ledger insert +
-- request verification happen in ONE transaction.

create or replace function public.verify_manual_wallet_top_up(
  p_top_up_id uuid,
  p_approve boolean,
  p_rejection_reason text default null
)
returns public.wallet_top_up_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.wallet_top_up_requests;
  v_admin uuid := auth.uid();
begin
  if v_admin is null then
    raise exception 'Not authenticated';
  end if;

  -- TODO: replace this with your project's real admin check.
  -- Example:
  -- if not exists (
  --   select 1 from public.users
  --   where id = v_admin and role = 'admin'
  -- ) then
  --   raise exception 'Admin access required';
  -- end if;

  select *
  into v_request
  from public.wallet_top_up_requests
  where id = p_top_up_id
  for update;

  if not found then
    raise exception 'Top-up request not found';
  end if;

  if v_request.status <> 'submitted' then
    raise exception 'This top-up is already processed';
  end if;

  if p_approve then

    -- ==============================================================
    -- WALLET CREDIT
    -- Keep this update only if your users table uses wallet_balance.
    -- ==============================================================
    update public.users
    set wallet_balance = coalesce(wallet_balance, 0) + v_request.amount
    where id = v_request.user_id;

    if not found then
      raise exception 'User wallet record not found';
    end if;

    -- ==============================================================
    -- LEDGER INSERT
    -- CHANGE THIS BLOCK to match your existing wallet_transactions
    -- columns. Do not skip the ledger entry.
    --
    -- Example only:
    --
    -- insert into public.wallet_transactions
    --   (user_id, amount, type, description, reference_id)
    -- values
    --   (v_request.user_id, v_request.amount, 'credit',
    --    'Manual JazzCash wallet top-up', v_request.id::text);
    --
    -- ==============================================================

    update public.wallet_top_up_requests
    set
      status = 'verified',
      verified_at = now(),
      verified_by = v_admin,
      rejection_reason = null
    where id = v_request.id
    returning * into v_request;

  else

    update public.wallet_top_up_requests
    set
      status = 'rejected',
      verified_at = now(),
      verified_by = v_admin,
      rejection_reason = nullif(trim(coalesce(p_rejection_reason, '')), '')
    where id = v_request.id
    returning * into v_request;

  end if;

  return v_request;
end;
$$;

revoke all on function public.verify_manual_wallet_top_up(uuid, boolean, text)
from public;

grant execute on function public.verify_manual_wallet_top_up(uuid, boolean, text)
to authenticated;

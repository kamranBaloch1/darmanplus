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
    provider,
    amount,
    amount_minor,
    currency,
    payment_method,
    receipt_url,
    status,
    submitted_at
  )
  values (
    auth.uid(),
    'jazzcash',
    null,
    null,
    'PKR',
    'jazzcash_manual',
    trim(p_receipt_url),
    'pending',
    now()
  )
  returning * into v_row;

  return v_row;
end;
$$;

revoke all on function public.create_manual_wallet_top_up(text)
from public;

grant execute on function public.create_manual_wallet_top_up(text)
to authenticated;
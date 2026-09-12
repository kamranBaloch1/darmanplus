create or replace function public.get_my_wallet_transactions(
  p_limit integer default 50,
  p_before timestamptz default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  current_user_id uuid := auth.uid();
  result jsonb;
begin
  if current_user_id is null then
    raise exception 'Authentication required';
  end if;

  if p_limit < 1 or p_limit > 100 then
    raise exception 'Transaction page size must be between 1 and 100';
  end if;

  select coalesce(jsonb_agg(items.item order by items.created_at desc), '[]'::jsonb)
  into result
  from (
    select
      to_jsonb(transaction_row) || jsonb_build_object(
        'counterpart_name',
        case
          when booking.patient_id = current_user_id then doctor_user.name
          when booking.doctor_id = current_user_id then patient_user.name
          else null
        end
      ) as item,
      transaction_row.created_at
    from public.wallet_transactions transaction_row
    left join public.bookings booking
      on booking.id = transaction_row.booking_id
    left join public.users patient_user
      on patient_user.uid = booking.patient_id
    left join public.users doctor_user
      on doctor_user.uid = booking.doctor_id
    where transaction_row.user_id = current_user_id
      and (p_before is null or transaction_row.created_at < p_before)
    order by transaction_row.created_at desc
    limit p_limit
  ) items;

  return result;
end;
$$;

revoke all on function public.get_my_wallet_transactions(integer, timestamptz) from public;
grant execute on function public.get_my_wallet_transactions(integer, timestamptz) to authenticated;

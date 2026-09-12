begin;

-- Safety check: stop if either tester profile is missing.
do $$
begin
  if (
    select count(*)
    from public.users
    where uid in (
      '9b9dd1ed-c6a2-459a-9035-a209f350c0b8',
      '364705c0-2319-468d-8871-d17bb2a33c25'
    )
  ) <> 2 then
    raise exception 'Cleanup stopped: both tester profiles were not found';
  end if;
end;
$$;

-- Clear consultations, chats, calls, wallet history and temporary records.
-- All related tables are truncated together to handle their foreign keys.
truncate table
  public.chat_messages,
  public.chat_rooms,
  public.consultation_call_invites,
  public.consultation_ratings,
  public.wallet_transactions,
  public.wallet_top_up_requests,
  public.bookings,
  public.push_notification_tokens,
  public.phone_otp_rate_limits
restart identity;

-- Remove every public profile except the two testers.
delete from public.users
where uid not in (
  '9b9dd1ed-c6a2-459a-9035-a209f350c0b8',
  '364705c0-2319-468d-8871-d17bb2a33c25'
);

-- Remove their corresponding authentication accounts and sessions.
delete from auth.users
where id not in (
  '9b9dd1ed-c6a2-459a-9035-a209f350c0b8',
  '364705c0-2319-468d-8871-d17bb2a33c25'
);

commit;
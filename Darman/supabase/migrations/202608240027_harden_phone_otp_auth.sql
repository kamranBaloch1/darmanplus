create table if not exists public.phone_otp_rate_limits (
  rate_key text primary key,
  window_started_at timestamptz not null default now(),
  attempts integer not null default 1 check (attempts > 0),
  updated_at timestamptz not null default now()
);

alter table public.phone_otp_rate_limits enable row level security;

revoke all on table public.phone_otp_rate_limits from anon, authenticated;
grant all on table public.phone_otp_rate_limits to service_role;

create or replace function public.consume_phone_otp_rate_limit(
  p_key text,
  p_limit integer,
  p_window_seconds integer
)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  next_attempts integer;
begin
  if p_key is null or length(p_key) < 10 or
     p_limit < 1 or p_window_seconds < 1 then
    return false;
  end if;

  insert into public.phone_otp_rate_limits as limits (
    rate_key,
    window_started_at,
    attempts,
    updated_at
  ) values (
    p_key,
    now(),
    1,
    now()
  )
  on conflict (rate_key) do update
  set
    attempts = case
      when limits.window_started_at <=
           now() - make_interval(secs => p_window_seconds)
        then 1
      else limits.attempts + 1
    end,
    window_started_at = case
      when limits.window_started_at <=
           now() - make_interval(secs => p_window_seconds)
        then now()
      else limits.window_started_at
    end,
    updated_at = now()
  returning attempts into next_attempts;

  return next_attempts <= p_limit;
end;
$$;

revoke all on function public.consume_phone_otp_rate_limit(text, integer, integer)
  from public, anon, authenticated;
grant execute on function public.consume_phone_otp_rate_limit(text, integer, integer)
  to service_role;

create or replace function public.get_auth_user_id_by_phone(p_phone text)
returns uuid
language sql
stable
security definer
set search_path = public, auth
as $$
  select id
  from auth.users
  where phone = p_phone
  limit 1;
$$;

revoke all on function public.get_auth_user_id_by_phone(text)
  from public, anon, authenticated;
grant execute on function public.get_auth_user_id_by_phone(text)
  to service_role;

create index if not exists phone_otp_rate_limits_updated_at_idx
  on public.phone_otp_rate_limits (updated_at);

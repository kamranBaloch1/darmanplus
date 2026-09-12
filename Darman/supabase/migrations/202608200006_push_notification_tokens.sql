create table if not exists public.push_notification_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(uid) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android', 'ios')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists push_notification_tokens_user_idx
  on public.push_notification_tokens(user_id);

alter table public.push_notification_tokens enable row level security;

create or replace function public.register_push_token(
  p_token text,
  p_platform text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(p_token), '') is null then
    raise exception 'Push token is required';
  end if;

  if p_platform not in ('android', 'ios') then
    raise exception 'Unsupported push platform';
  end if;

  insert into public.push_notification_tokens (
    user_id,
    token,
    platform,
    updated_at
  ) values (
    auth.uid(),
    trim(p_token),
    p_platform,
    now()
  )
  on conflict (token) do update
  set user_id = excluded.user_id,
      platform = excluded.platform,
      updated_at = now();
end;
$$;

create or replace function public.unregister_push_token(p_token text)
returns void
language sql
security definer
set search_path = public
as $$
  delete from public.push_notification_tokens
  where token = trim(p_token)
    and user_id = auth.uid();
$$;

revoke all on table public.push_notification_tokens from anon, authenticated;
revoke all on function public.register_push_token(text, text) from public;
revoke all on function public.unregister_push_token(text) from public;
grant execute on function public.register_push_token(text, text) to authenticated;
grant execute on function public.unregister_push_token(text) to authenticated;

begin;

create or replace function public.block_refunded_consultation_messages()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.type <> 'system' and exists (
    select 1
    from public.bookings booking
    where booking.id = new.booking_id
      and booking.admin_refunded_at is not null
  ) then
    raise exception 'Refunded consultation chat is read-only';
  end if;

  return new;
end;
$$;

drop trigger if exists block_refunded_consultation_messages
  on public.chat_messages;
create trigger block_refunded_consultation_messages
before insert on public.chat_messages
for each row execute function public.block_refunded_consultation_messages();

revoke all on function public.block_refunded_consultation_messages()
  from public, anon, authenticated;

commit;

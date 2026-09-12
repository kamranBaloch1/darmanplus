begin;

alter table public.users
  add column if not exists doctor_completed_consultation_count integer not null default 0
  check (doctor_completed_consultation_count >= 0);

update public.users u
set doctor_completed_consultation_count = (
  select count(*)::integer
  from public.bookings b
  where b.doctor_id = u.uid and b.status = 'completed'
)
where u.role = 'doctor';

create or replace function public.update_doctor_completed_consultation_count()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if new.status = 'completed' and old.status is distinct from 'completed' then
    update public.users
    set doctor_completed_consultation_count = doctor_completed_consultation_count + 1
    where uid = new.doctor_id;
  elsif old.status = 'completed' and new.status is distinct from 'completed' then
    update public.users
    set doctor_completed_consultation_count = greatest(
      doctor_completed_consultation_count - 1,
      0
    )
    where uid = new.doctor_id;
  end if;
  return new;
end;
$$;

drop trigger if exists bookings_update_doctor_completed_count on public.bookings;
create trigger bookings_update_doctor_completed_count
after update of status on public.bookings
for each row execute function public.update_doctor_completed_consultation_count();

commit;

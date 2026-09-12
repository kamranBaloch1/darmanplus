begin;

create or replace function public.enforce_doctor_profile_availability()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.role = 'doctor' then
    if new.is_profile_completed is not true then
      if old.is_available is distinct from new.is_available
         and new.is_available is true then
        raise exception 'Complete your profile before going online';
      end if;
      new.is_available := false;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_doctor_profile_availability on public.users;
create trigger enforce_doctor_profile_availability
before update of is_available, is_profile_completed on public.users
for each row
execute function public.enforce_doctor_profile_availability();

update public.users
set is_available = false,
    updated_at = now()
where role = 'doctor'
  and is_profile_completed is not true
  and is_available is true;

commit;

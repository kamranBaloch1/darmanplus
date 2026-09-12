begin;

create or replace function public.set_call_invite_participant_names()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  caller_profile_name text;
  callee_profile_name text;
begin
  select nullif(btrim(name), '')
  into caller_profile_name
  from public.users
  where uid = new.caller_id;

  select nullif(btrim(name), '')
  into callee_profile_name
  from public.users
  where uid = new.callee_id;

  new.caller_name := coalesce(
    caller_profile_name,
    case when new.caller_is_doctor then 'Doctor' else 'Patient' end
  );
  new.callee_name := coalesce(
    callee_profile_name,
    case when new.callee_is_doctor then 'Doctor' else 'Patient' end
  );

  return new;
end;
$$;

drop trigger if exists set_call_invite_participant_names
  on public.consultation_call_invites;
create trigger set_call_invite_participant_names
before insert or update of caller_id, callee_id, caller_is_doctor, callee_is_doctor
on public.consultation_call_invites
for each row
execute function public.set_call_invite_participant_names();

update public.consultation_call_invites as invite
set caller_name = coalesce(
      nullif(btrim(caller_user.name), ''),
      case when invite.caller_is_doctor then 'Doctor' else 'Patient' end
    ),
    callee_name = coalesce(
      nullif(btrim(callee_user.name), ''),
      case when invite.callee_is_doctor then 'Doctor' else 'Patient' end
    )
from public.users as caller_user,
     public.users as callee_user
where caller_user.uid = invite.caller_id
  and callee_user.uid = invite.callee_id;

revoke all on function public.set_call_invite_participant_names() from public;

commit;

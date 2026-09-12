begin;

alter table public.consultation_ratings
  add column if not exists doctor_seen_at timestamptz;

-- Existing ratings predate this inbox behavior and must not flood doctors
-- with historical dialogs immediately after deployment.
update public.consultation_ratings
set doctor_seen_at = now()
where doctor_seen_at is null;

alter table public.consultation_ratings replica identity full;

do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'consultation_ratings'
  ) then
    alter publication supabase_realtime
      add table public.consultation_ratings;
  end if;
end;
$$;

create or replace function public.acknowledge_doctor_rating(p_rating_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.consultation_ratings
  set doctor_seen_at = coalesce(doctor_seen_at, now())
  where id = p_rating_id
    and doctor_id = auth.uid();

  if not found then
    raise exception 'Rating not found or access denied';
  end if;
end;
$$;

revoke all on function public.acknowledge_doctor_rating(uuid) from public;
grant execute on function public.acknowledge_doctor_rating(uuid) to authenticated;

commit;

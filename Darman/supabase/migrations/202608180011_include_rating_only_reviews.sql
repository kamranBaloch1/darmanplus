begin;

update public.users u
set doctor_review_count = (
  select count(*)::integer
  from public.consultation_ratings r
  where r.doctor_id = u.uid
)
where u.role = 'doctor';

create or replace function public.get_doctor_reviews(
  p_doctor_id uuid,
  p_limit integer default 20,
  p_offset integer default 0
)
returns table (
  id uuid,
  booking_id uuid,
  patient_id uuid,
  doctor_id uuid,
  rating smallint,
  review text,
  patient_name text,
  created_at timestamptz,
  updated_at timestamptz
)
language sql
security definer
set search_path = public, auth
stable
as $$
  select
    r.id, r.booking_id, r.patient_id, r.doctor_id, r.rating, r.review,
    coalesce(nullif(split_part(u.name, ' ', 1), ''), 'Patient') as patient_name,
    r.created_at, r.updated_at
  from public.consultation_ratings r
  join public.users u on u.uid = r.patient_id
  where r.doctor_id = p_doctor_id
    and auth.uid() is not null
  order by r.created_at desc
  limit least(greatest(p_limit, 1), 100)
  offset greatest(p_offset, 0);
$$;

create or replace function public.get_doctor_review_summary(p_doctor_id uuid)
returns jsonb
language sql
security definer
set search_path = public
stable
as $$
  select jsonb_build_object(
    'average_rating', coalesce(round(avg(rating)::numeric, 2), 0),
    'review_count', count(*)::integer,
    'five_star_count', count(*) filter (where rating = 5)::integer,
    'four_star_count', count(*) filter (where rating = 4)::integer,
    'three_star_count', count(*) filter (where rating = 3)::integer,
    'two_star_count', count(*) filter (where rating = 2)::integer,
    'one_star_count', count(*) filter (where rating = 1)::integer
  )
  from public.consultation_ratings
  where doctor_id = p_doctor_id
    and auth.uid() is not null;
$$;

drop function if exists public.submit_consultation_rating(uuid, integer, text);
create function public.submit_consultation_rating(
  p_booking_id uuid,
  p_rating integer,
  p_review text default null
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  clean_review text;
begin
  if p_rating < 1 or p_rating > 5 then raise exception 'Rating must be between 1 and 5'; end if;
  clean_review := nullif(btrim(coalesce(p_review, '')), '');
  if clean_review is not null and char_length(clean_review) > 1000 then
    raise exception 'Review cannot be longer than 1,000 characters';
  end if;
  select * into b from public.bookings where id = p_booking_id;
  if not found or auth.uid() <> b.patient_id then raise exception 'Access denied'; end if;
  if b.status <> 'completed' then raise exception 'Complete the consultation before rating'; end if;

  insert into public.consultation_ratings (booking_id, patient_id, doctor_id, rating, review)
  values (b.id, b.patient_id, b.doctor_id, p_rating, clean_review)
  on conflict (booking_id) do update
    set rating = excluded.rating, review = excluded.review, updated_at = now()
    where public.consultation_ratings.patient_id = auth.uid();

  update public.users
  set doctor_rating = coalesce((
        select round(avg(rating)::numeric, 2)
        from public.consultation_ratings where doctor_id = b.doctor_id
      ), 0),
      doctor_review_count = (
        select count(*)::integer
        from public.consultation_ratings where doctor_id = b.doctor_id
      )
  where uid = b.doctor_id;
end;
$$;

revoke all on function public.get_doctor_reviews(uuid, integer, integer) from public;
revoke all on function public.get_doctor_review_summary(uuid) from public;
revoke all on function public.submit_consultation_rating(uuid, integer, text) from public;
grant execute on function public.get_doctor_reviews(uuid, integer, integer) to authenticated;
grant execute on function public.get_doctor_review_summary(uuid) to authenticated;
grant execute on function public.submit_consultation_rating(uuid, integer, text) to authenticated;

commit;

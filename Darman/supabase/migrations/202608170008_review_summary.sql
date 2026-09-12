begin;

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
    and nullif(btrim(review), '') is not null
    and auth.uid() is not null;
$$;

revoke all on function public.get_doctor_review_summary(uuid) from public;
grant execute on function public.get_doctor_review_summary(uuid) to authenticated;

commit;

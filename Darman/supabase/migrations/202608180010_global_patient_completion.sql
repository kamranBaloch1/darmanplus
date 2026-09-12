begin;

create or replace function public.get_consultation_completion(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  is_doctor boolean;
  already_rated boolean;
  doctor_name_value text;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found or auth.uid() not in (b.patient_id, b.doctor_id) then
    raise exception 'Access denied';
  end if;
  if b.status <> 'completed' then
    raise exception 'Consultation is not completed';
  end if;

  is_doctor := auth.uid() = b.doctor_id;
  select exists(
    select 1 from public.consultation_ratings where booking_id = b.id
  ) into already_rated;
  select coalesce(nullif(name, ''), 'Doctor') into doctor_name_value
  from public.users where uid = b.doctor_id;

  return jsonb_build_object(
    'booking_id', b.id,
    'doctor_name', coalesce(doctor_name_value, 'Doctor'),
    'gross_fee', coalesce(b.gross_fee, b.consultation_fee),
    'commission_rate', coalesce(b.commission_rate, 0.20),
    'commission_amount', coalesce(
      b.commission_amount,
      round(b.consultation_fee::numeric * 0.20, 2)
    ),
    'doctor_earning', coalesce(
      b.doctor_earning,
      round(b.consultation_fee::numeric * 0.80, 2)
    ),
    'completed_at', b.completed_at,
    'is_doctor', is_doctor,
    'should_show', case
      when is_doctor then b.doctor_receipt_seen_at is null
      else b.patient_receipt_seen_at is null
    end,
    'already_rated', already_rated
  );
end;
$$;

revoke all on function public.get_consultation_completion(uuid) from public;
grant execute on function public.get_consultation_completion(uuid) to authenticated;

commit;

begin;

alter table public.bookings
  add column if not exists gross_fee numeric(12,2),
  add column if not exists commission_rate numeric(5,4),
  add column if not exists commission_amount numeric(12,2),
  add column if not exists doctor_earning numeric(12,2),
  add column if not exists patient_receipt_seen_at timestamptz,
  add column if not exists doctor_receipt_seen_at timestamptz;

create table if not exists public.wallet_transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.users(uid) on delete set null,
  booking_id uuid references public.bookings(id) on delete restrict,
  transaction_type text not null check (
    transaction_type in ('wallet_top_up', 'consultation_payment', 'doctor_earning', 'platform_commission')
  ),
  currency text not null default 'PKR' check (currency = 'PKR'),
  amount numeric(12,2) not null,
  balance_after numeric(12,2),
  reserved_balance_after numeric(12,2),
  description text not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (booking_id, transaction_type),
  check (
    (transaction_type = 'wallet_top_up' and booking_id is null and user_id is not null)
    or
    (transaction_type <> 'wallet_top_up' and booking_id is not null)
  )
);

alter table public.wallet_transactions enable row level security;
drop policy if exists "Users can view their wallet transactions"
  on public.wallet_transactions;
create policy "Users can view their wallet transactions"
  on public.wallet_transactions for select
  using (auth.uid() = user_id);
grant select on public.wallet_transactions to authenticated;

create table if not exists public.consultation_ratings (
  id uuid primary key default gen_random_uuid(),
  booking_id uuid not null unique references public.bookings(id) on delete cascade,
  patient_id uuid not null references public.users(uid) on delete cascade,
  doctor_id uuid not null references public.users(uid) on delete cascade,
  rating smallint not null check (rating between 1 and 5),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.consultation_ratings enable row level security;
drop policy if exists "Participants can view consultation ratings"
  on public.consultation_ratings;
create policy "Participants can view consultation ratings"
  on public.consultation_ratings for select
  using (auth.uid() in (patient_id, doctor_id));
grant select on public.consultation_ratings to authenticated;

drop function if exists public.end_video_consultation(uuid);
create function public.end_video_consultation(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  b public.bookings%rowtype;
  patient_balance numeric(12,2);
  patient_reserved numeric(12,2);
  doctor_balance numeric(12,2);
  gross numeric(12,2);
  commission numeric(12,2);
  earning numeric(12,2);
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;

  select * into b from public.bookings where id = p_booking_id for update;
  if not found then raise exception 'Booking not found'; end if;
  if auth.uid() <> b.doctor_id then
    raise exception 'Only the assigned doctor can end the consultation';
  end if;

  if b.status = 'completed' then
    return jsonb_build_object(
      'booking_id', b.id, 'gross_fee', b.gross_fee,
      'commission_rate', b.commission_rate,
      'commission_amount', b.commission_amount,
      'doctor_earning', b.doctor_earning,
      'completed_at', b.completed_at
    );
  end if;
  if b.status <> 'inProgress' then
    raise exception 'The consultation is not in progress';
  end if;

  perform 1 from public.users
  where uid in (b.patient_id, b.doctor_id)
  order by uid for update;

  select coalesce(wallet_balance, 0), coalesce(wallet_reserved_balance, 0)
    into patient_balance, patient_reserved
  from public.users where uid = b.patient_id;
  select coalesce(wallet_balance, 0)
    into doctor_balance
  from public.users where uid = b.doctor_id;

  gross := round(coalesce(b.consultation_fee, 0)::numeric, 2);
  if gross <= 0 then raise exception 'The consultation fee is invalid'; end if;
  if patient_reserved < gross then
    raise exception 'Reserved wallet funds are insufficient; settlement was not completed';
  end if;

  commission := round(gross * 0.20, 2);
  earning := gross - commission;

  update public.users
  set wallet_reserved_balance = patient_reserved - gross
  where uid = b.patient_id;

  update public.users
  set wallet_balance = doctor_balance + earning
  where uid = b.doctor_id;

  update public.bookings set
    status = 'completed',
    completed_at = now(),
    call_ended_at = now(),
    gross_fee = gross,
    commission_rate = 0.20,
    commission_amount = commission,
    doctor_earning = earning,
    updated_at = now()
  where id = b.id;

  insert into public.wallet_transactions (
    user_id, booking_id, transaction_type, amount, balance_after,
    reserved_balance_after, description, metadata
  ) values
  (
    b.patient_id, b.id, 'consultation_payment', -gross, patient_balance,
    patient_reserved - gross, 'Consultation payment completed',
    jsonb_build_object('doctor_id', b.doctor_id)
  ),
  (
    b.doctor_id, b.id, 'doctor_earning', earning, doctor_balance + earning,
    null, 'Consultation earning credited',
    jsonb_build_object('gross_fee', gross, 'commission', commission)
  ),
  (
    null, b.id, 'platform_commission', commission, null,
    null, 'Platform commission collected',
    jsonb_build_object('rate', 0.20, 'patient_id', b.patient_id, 'doctor_id', b.doctor_id)
  );

  return jsonb_build_object(
    'booking_id', b.id, 'gross_fee', gross, 'commission_rate', 0.20,
    'commission_amount', commission, 'doctor_earning', earning,
    'completed_at', now()
  );
end;
$$;

create or replace function public.get_consultation_completion(p_booking_id uuid)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare b public.bookings%rowtype; is_doctor boolean; already_rated boolean;
begin
  select * into b from public.bookings where id = p_booking_id;
  if not found or auth.uid() not in (b.patient_id, b.doctor_id) then
    raise exception 'Access denied';
  end if;
  if b.status <> 'completed' then raise exception 'Consultation is not completed'; end if;
  is_doctor := auth.uid() = b.doctor_id;
  select exists(
    select 1 from public.consultation_ratings where booking_id = b.id
  ) into already_rated;
  return jsonb_build_object(
    'booking_id', b.id,
    'gross_fee', coalesce(b.gross_fee, b.consultation_fee),
    'commission_rate', coalesce(b.commission_rate, 0.20),
    'commission_amount', coalesce(b.commission_amount, round(b.consultation_fee::numeric * 0.20, 2)),
    'doctor_earning', coalesce(b.doctor_earning, round(b.consultation_fee::numeric * 0.80, 2)),
    'completed_at', b.completed_at,
    'is_doctor', is_doctor,
    'should_show', case when is_doctor then b.doctor_receipt_seen_at is null else b.patient_receipt_seen_at is null end,
    'already_rated', already_rated
  );
end;
$$;

create or replace function public.acknowledge_consultation_completion(p_booking_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.bookings set
    doctor_receipt_seen_at = case when auth.uid() = doctor_id then coalesce(doctor_receipt_seen_at, now()) else doctor_receipt_seen_at end,
    patient_receipt_seen_at = case when auth.uid() = patient_id then coalesce(patient_receipt_seen_at, now()) else patient_receipt_seen_at end
  where id = p_booking_id and auth.uid() in (patient_id, doctor_id);
  if not found then raise exception 'Access denied'; end if;
end;
$$;

create or replace function public.submit_consultation_rating(p_booking_id uuid, p_rating integer)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare b public.bookings%rowtype;
begin
  if p_rating < 1 or p_rating > 5 then raise exception 'Rating must be between 1 and 5'; end if;
  select * into b from public.bookings where id = p_booking_id;
  if not found or auth.uid() <> b.patient_id then raise exception 'Access denied'; end if;
  if b.status <> 'completed' then raise exception 'Complete the consultation before rating'; end if;

  insert into public.consultation_ratings (booking_id, patient_id, doctor_id, rating)
  values (b.id, b.patient_id, b.doctor_id, p_rating)
  on conflict (booking_id) do update
    set rating = excluded.rating, updated_at = now()
    where public.consultation_ratings.patient_id = auth.uid();

  update public.users
  set doctor_rating = coalesce((
    select round(avg(rating)::numeric, 2)
    from public.consultation_ratings where doctor_id = b.doctor_id
  ), 0)
  where uid = b.doctor_id;
end;
$$;

revoke all on function public.end_video_consultation(uuid) from public;
revoke all on function public.get_consultation_completion(uuid) from public;
revoke all on function public.acknowledge_consultation_completion(uuid) from public;
revoke all on function public.submit_consultation_rating(uuid, integer) from public;
grant execute on function public.end_video_consultation(uuid) to authenticated;
grant execute on function public.get_consultation_completion(uuid) to authenticated;
grant execute on function public.acknowledge_consultation_completion(uuid) to authenticated;
grant execute on function public.submit_consultation_rating(uuid, integer) to authenticated;

commit;

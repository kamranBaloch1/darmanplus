begin;

create table if not exists public.doctor_withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.users(uid) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'PKR',
  bank_name text not null,
  account_number text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'rejected')),
  requested_at timestamptz not null default now(),
  processed_at timestamptz,
  processed_by text,
  rejection_reason text,
  wallet_transaction_id uuid references public.wallet_transactions(id) on delete restrict,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists doctor_withdrawal_requests_status_idx
  on public.doctor_withdrawal_requests(status, created_at desc);
create index if not exists doctor_withdrawal_requests_doctor_idx
  on public.doctor_withdrawal_requests(doctor_id, created_at desc);

alter table public.doctor_withdrawal_requests enable row level security;
create policy "Doctors can view own withdrawal requests"
  on public.doctor_withdrawal_requests for select to authenticated
  using (doctor_id = auth.uid());
revoke insert, update, delete on public.doctor_withdrawal_requests from authenticated;

create or replace function public.create_doctor_withdrawal_request(
  p_amount numeric,
  p_bank_name text,
  p_account_number text
) returns public.doctor_withdrawal_requests
language plpgsql
security definer
set search_path = public
as $$
declare
  v_doctor public.users%rowtype;
  v_request public.doctor_withdrawal_requests;
  v_amount numeric(12,2) := round(coalesce(p_amount, 0), 2);
  v_bank text := btrim(coalesce(p_bank_name, ''));
  v_account text := btrim(coalesce(p_account_number, ''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if v_amount <= 0 then raise exception 'Enter a valid withdrawal amount'; end if;
  if char_length(v_bank) < 2 or char_length(v_bank) > 80 then raise exception 'Choose a valid bank or wallet'; end if;
  if char_length(v_account) < 5 or char_length(v_account) > 40 then raise exception 'Enter a valid account number'; end if;

  select * into v_doctor from public.users where uid = auth.uid() for update;
  if not found or v_doctor.role <> 'doctor' then raise exception 'Only doctors can request a withdrawal'; end if;
  if coalesce(v_doctor.wallet_balance, 0) < v_amount then raise exception 'Your available wallet balance is not enough for this withdrawal'; end if;

  update public.users
  set wallet_balance = coalesce(wallet_balance, 0) - v_amount,
      wallet_reserved_balance = coalesce(wallet_reserved_balance, 0) + v_amount,
      updated_at = now()
  where uid = v_doctor.uid;

  insert into public.doctor_withdrawal_requests (doctor_id, amount, bank_name, account_number)
  values (v_doctor.uid, v_amount, v_bank, v_account)
  returning * into v_request;
  return v_request;
end;
$$;

create or replace function public.admin_process_doctor_withdrawal_request(
  p_request_id uuid,
  p_action text,
  p_reason text,
  p_admin_email text
) returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_request public.doctor_withdrawal_requests%rowtype;
  v_balance numeric(12,2);
  v_transaction_id uuid;
  v_reason text := btrim(coalesce(p_reason, ''));
begin
  if auth.role() <> 'service_role' then raise exception 'Only the admin payment service can process withdrawals'; end if;
  if p_action not in ('approve', 'reject') then raise exception 'Choose approve or reject'; end if;
  if p_action = 'reject' and char_length(v_reason) < 5 then raise exception 'Provide a rejection reason'; end if;

  select * into v_request from public.doctor_withdrawal_requests where id = p_request_id for update;
  if not found then raise exception 'Withdrawal request not found'; end if;
  if v_request.status <> 'pending' then raise exception 'This withdrawal request has already been processed'; end if;
  select coalesce(wallet_balance, 0) into v_balance from public.users where uid = v_request.doctor_id for update;

  if p_action = 'approve' then
    insert into public.wallet_transactions (
      user_id, transaction_type, amount, balance_after, reserved_balance_after, description, metadata
    ) values (
      v_request.doctor_id, 'wallet_top_up_reversal', -v_request.amount, v_balance,
      greatest(coalesce((select wallet_reserved_balance from public.users where uid = v_request.doctor_id), 0) - v_request.amount, 0),
      'Doctor withdrawal paid to ' || v_request.bank_name,
      jsonb_build_object('ledger_kind', 'doctor_withdrawal', 'withdrawal_request_id', v_request.id, 'bank_name', v_request.bank_name, 'account_number', v_request.account_number, 'admin_email', lower(btrim(p_admin_email)))
    ) returning id into v_transaction_id;

    update public.users set wallet_reserved_balance = greatest(coalesce(wallet_reserved_balance, 0) - v_request.amount, 0), updated_at = now() where uid = v_request.doctor_id;
    update public.doctor_withdrawal_requests set status = 'approved', processed_at = now(), processed_by = lower(btrim(p_admin_email)), wallet_transaction_id = v_transaction_id, updated_at = now() where id = v_request.id;
  else
    update public.users set wallet_balance = coalesce(wallet_balance, 0) + v_request.amount, wallet_reserved_balance = greatest(coalesce(wallet_reserved_balance, 0) - v_request.amount, 0), updated_at = now() where uid = v_request.doctor_id;
    update public.doctor_withdrawal_requests set status = 'rejected', rejection_reason = v_reason, processed_at = now(), processed_by = lower(btrim(p_admin_email)), updated_at = now() where id = v_request.id;
  end if;

  return jsonb_build_object('doctor_id', v_request.doctor_id, 'amount', v_request.amount, 'status', case when p_action = 'approve' then 'approved' else 'rejected' end, 'bank_name', v_request.bank_name);
end;
$$;

revoke all on function public.create_doctor_withdrawal_request(numeric, text, text) from public;
grant execute on function public.create_doctor_withdrawal_request(numeric, text, text) to authenticated;
revoke all on function public.admin_process_doctor_withdrawal_request(uuid, text, text, text) from public, anon, authenticated;
grant execute on function public.admin_process_doctor_withdrawal_request(uuid, text, text, text) to service_role;

commit;

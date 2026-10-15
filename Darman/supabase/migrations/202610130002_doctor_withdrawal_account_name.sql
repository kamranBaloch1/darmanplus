begin;

alter table public.doctor_withdrawal_requests add column if not exists account_name text;

create or replace function public.create_doctor_withdrawal_request(p_amount numeric, p_bank_name text, p_account_number text, p_account_name text)
returns public.doctor_withdrawal_requests language plpgsql security definer set search_path = public as $$
declare v_doctor public.users%rowtype; v_request public.doctor_withdrawal_requests; v_amount numeric(12,2) := round(coalesce(p_amount, 0), 2); v_bank text := btrim(coalesce(p_bank_name, '')); v_account text := btrim(coalesce(p_account_number, '')); v_name text := btrim(coalesce(p_account_name, ''));
begin
  if auth.uid() is null then raise exception 'Authentication required'; end if;
  if v_amount <= 0 then raise exception 'Enter a valid withdrawal amount'; end if;
  if char_length(v_bank) < 2 or char_length(v_bank) > 80 then raise exception 'Choose a valid bank or wallet'; end if;
  if char_length(v_account) < 5 or char_length(v_account) > 40 then raise exception 'Enter a valid account number'; end if;
  if char_length(v_name) < 2 or char_length(v_name) > 100 then raise exception 'Enter the account holder name'; end if;
  select * into v_doctor from public.users where uid = auth.uid() for update;
  if not found or v_doctor.role <> 'doctor' then raise exception 'Only doctors can request a withdrawal'; end if;
  if coalesce(v_doctor.wallet_balance, 0) < v_amount then raise exception 'Your available wallet balance is not enough for this withdrawal'; end if;
  update public.users set wallet_balance = coalesce(wallet_balance, 0) - v_amount, wallet_reserved_balance = coalesce(wallet_reserved_balance, 0) + v_amount, updated_at = now() where uid = v_doctor.uid;
  insert into public.doctor_withdrawal_requests (doctor_id, amount, bank_name, account_number, account_name) values (v_doctor.uid, v_amount, v_bank, v_account, v_name) returning * into v_request;
  return v_request;
end;
$$;

revoke all on function public.create_doctor_withdrawal_request(numeric, text, text) from public;
revoke all on function public.create_doctor_withdrawal_request(numeric, text, text, text) from public;
grant execute on function public.create_doctor_withdrawal_request(numeric, text, text, text) to authenticated;

commit;

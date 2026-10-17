begin;

create table if not exists public.manual_payment_settings (
  setting_key text primary key check (setting_key = 'jazzcash_qr'),
  storage_path text not null,
  updated_at timestamptz not null default now()
);

alter table public.manual_payment_settings enable row level security;
revoke all on public.manual_payment_settings from anon, authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('manual-payment-qr', 'manual-payment-qr', false, 5242880, array['image/jpeg', 'image/png', 'image/webp'])
on conflict (id) do update set
  public = false,
  file_size_limit = 5242880,
  allowed_mime_types = array['image/jpeg', 'image/png', 'image/webp'];

commit;

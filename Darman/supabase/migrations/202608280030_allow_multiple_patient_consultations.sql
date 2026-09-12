begin;

-- Patients may create a new booking and later start it while another
-- consultation is still active. Same-doctor duplicate booking protection
-- remains in the application and existing booking constraints.
drop trigger if exists prevent_booking_during_active_consultation
  on public.bookings;
drop function if exists public.prevent_booking_during_active_consultation();

drop index if exists public.one_in_progress_consultation_per_patient;

commit;

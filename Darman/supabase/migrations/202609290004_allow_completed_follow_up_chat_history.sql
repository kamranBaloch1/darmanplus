begin;

create or replace function public.ensure_chat_room(p_booking_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  booking public.bookings%rowtype;
  room_id uuid;
  local_today date := (now() at time zone 'Asia/Karachi')::date;
  history_visible boolean;
  active_chat boolean;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into booking
  from public.bookings
  where id = p_booking_id;

  if not found or auth.uid() not in (booking.patient_id, booking.doctor_id) then
    raise exception 'Access denied';
  end if;

  -- Completed and cancelled consultations always retain readable chat history.
  history_visible := booking.status in ('completed', 'cancelled');
  active_chat := booking.status in ('pending', 'accepted', 'inProgress')
    or (
      booking.status = 'completed'
      and booking.follow_up_date is not null
      and booking.follow_up_date <= local_today
      and booking.follow_up_ended_at is null
      and booking.admin_refunded_at is null
    );

  if booking.status not in ('pending', 'accepted', 'inProgress')
     and not history_visible then
    raise exception 'This consultation chat is closed';
  end if;

  select id into room_id
  from public.chat_rooms
  where booking_id = booking.id
  order by created_at
  limit 1;

  if room_id is null then
    insert into public.chat_rooms (
      booking_id, patient_id, doctor_id, is_active
    ) values (
      booking.id, booking.patient_id, booking.doctor_id, active_chat
    ) returning id into room_id;
  else
    update public.chat_rooms
    set is_active = active_chat,
        updated_at = now()
    where id = room_id;
  end if;

  return room_id;
end;
$$;

revoke all on function public.ensure_chat_room(uuid) from public;
grant execute on function public.ensure_chat_room(uuid) to authenticated;

commit;

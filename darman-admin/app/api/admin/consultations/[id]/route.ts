import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean));

export async function GET(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!url || !service) return NextResponse.json({ error: "Admin server is not configured." }, { status: 500 });
  const client = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await client.auth.getUser(token);
  if (authError || !auth.user?.email || !admins.has(auth.user.email.toLowerCase())) {
    return NextResponse.json({ error: "Unauthorized." }, { status: 403 });
  }

  const { id } = await params;
  const { data: booking, error } = await client.from("bookings").select("*").eq("id", id).single();
  if (error) return NextResponse.json({ error: error.message }, { status: 404 });

  const [{ data: people }, { data: roomByBooking }, { data: rating }, { data: transactions }] = await Promise.all([
    client.from("users").select("uid,name,email,phone,profile_image,role").in("uid", [booking.doctor_id, booking.patient_id]),
    client.from("chat_rooms").select("*").eq("booking_id", id).maybeSingle(),
    client.from("consultation_ratings").select("*").eq("booking_id", id).maybeSingle(),
    client.from("wallet_transactions").select("*").eq("booking_id", id).order("created_at", { ascending: true }),
  ]);
  const room = roomByBooking ?? (booking.consultation_room_id
    ? (await client.from("chat_rooms").select("*").eq("id", booking.consultation_room_id).maybeSingle()).data
    : null);
  const { data: messageRows } = await client.from("chat_messages").select("*").eq("booking_id", id).order("created_at", { ascending: true });
  const messages = await Promise.all((messageRows ?? []).map(async message => {
    const mime = String(message.mime_type ?? "").toLowerCase();
    const isImage = message.type === "image" || mime.startsWith("image/");
    const isVoice = message.type === "voice" || mime.startsWith("audio/");
    if (message.is_deleted || !message.media_url) return message;
    if (isImage || isVoice) {
      return {
        ...message,
        attachment_kind: isImage ? "image" : "voice",
        media_url: null,
        media_signed_url: null,
      };
    }
    if (/^https?:\/\//i.test(message.media_url)) {
      return { ...message, media_signed_url: message.media_url };
    }
    const { data: signed } = await client.storage.from("chat-media").createSignedUrl(message.media_url, 3600);
    return { ...message, media_signed_url: signed?.signedUrl ?? null };
  }));

  return NextResponse.json({
    booking,
    doctor: people?.find(person => person.uid === booking.doctor_id) ?? null,
    patient: people?.find(person => person.uid === booking.patient_id) ?? null,
    chatRoom: room,
    messages,
    rating,
    transactions: transactions ?? [],
  });
}

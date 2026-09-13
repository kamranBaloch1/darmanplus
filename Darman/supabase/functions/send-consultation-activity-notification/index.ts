import { createClient } from "npm:@supabase/supabase-js@2";
import { sendPushToUser } from "../_shared/push.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    if (request.method !== "POST") {
      return Response.json(
        { error: "Method not allowed" },
        { status: 405, headers: corsHeaders },
      );
    }

    const authorization = request.headers.get("Authorization");
    if (!authorization) throw new Error("Authentication required");
    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: { user }, error: authError } =
      await userClient.auth.getUser();
    if (authError || !user) throw new Error("Authentication required");

    const body = await request.json();
    const event = body.event?.toString();
    if (event !== "chat_message" && event !== "patient_cancelled") {
      throw new Error("Unsupported activity event");
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    let bookingId: string;
    let recipientId: string;
    let title: string;
    let notificationBody: string;
    let notificationType: string;
    let senderName = "";
    let messageId = "";
    let chatRoomId = "";

    if (event === "chat_message") {
      messageId = body.message_id?.toString();
      if (!messageId) throw new Error("message_id is required");
      const { data: message, error: messageError } = await admin
        .from("chat_messages")
        .select(
          "id, booking_id, chat_room_id, sender_id, type, text, mime_type, created_at, is_deleted",
        )
        .eq("id", messageId)
        .single();
      if (messageError || !message) throw new Error("Message not found");
      if (message.sender_id !== user.id || message.type === "system") {
        throw new Error("Access denied");
      }
      if (message.is_deleted) throw new Error("Deleted messages are not notified");
      assertRecent(message.created_at, "message");

      const { data: booking, error: bookingError } = await admin
        .from("bookings")
        .select("id, patient_id, doctor_id")
        .eq("id", message.booking_id)
        .single();
      if (bookingError || !booking) throw new Error("Booking not found");
      if (user.id !== booking.patient_id && user.id !== booking.doctor_id) {
        throw new Error("Access denied");
      }

      recipientId = user.id === booking.patient_id
        ? booking.doctor_id
        : booking.patient_id;
      bookingId = booking.id;
      chatRoomId = message.chat_room_id;

      const { data: sender } = await admin
        .from("users")
        .select("name, role")
        .eq("uid", user.id)
        .maybeSingle();
      senderName = sender?.name?.trim() ||
        (sender?.role === "doctor" ? "Your doctor" : "Your patient");
      title = sender?.role === "doctor"
        ? `Message from ${senderName}`
        : `New message from ${senderName}`;
      notificationBody = messagePreview(message);
      notificationType = "chat_message";
    } else {
      bookingId = body.booking_id?.toString();
      if (!bookingId) throw new Error("booking_id is required");
      const { data: booking, error: bookingError } = await admin
        .from("bookings")
        .select(
          "id, patient_id, doctor_id, status, cancelled_by, cancelled_at",
        )
        .eq("id", bookingId)
        .single();
      if (bookingError || !booking) throw new Error("Booking not found");
      if (
        user.id !== booking.patient_id ||
        booking.cancelled_by !== user.id ||
        booking.status !== "cancelled"
      ) {
        throw new Error("Access denied");
      }
      assertRecent(booking.cancelled_at, "cancellation");

      const { data: patient } = await admin
        .from("users")
        .select("name")
        .eq("uid", booking.patient_id)
        .maybeSingle();
      senderName = patient?.name?.trim() || "The patient";
      recipientId = booking.doctor_id;
      title = "Consultation request cancelled";
      notificationBody = `${senderName} cancelled the consultation request.`;
      notificationType = "patient_cancelled_appointment";
    }

    const result = await sendPushToUser({
      admin,
      userId: recipientId,
      title,
      body: notificationBody,
      ttl: "86400s",
      channelId: event === "chat_message"
        ? "chat_messages_v2"
        : "consultation_requests_v2",
      data: {
        type: notificationType,
        booking_id: bookingId,
        sender_id: user.id,
        sender_name: senderName,
        message_id: messageId,
        chat_room_id: chatRoomId,
      },
    });

    return Response.json(
      {
        sent: result.sent,
        attempted: result.attempted,
        message: result.message,
        event,
      },
      { headers: corsHeaders },
    );
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Notification failed" },
      { status: 400, headers: corsHeaders },
    );
  }
});

function messagePreview(message: {
  type: string;
  text: string | null;
  mime_type: string | null;
}) {
  const text = message.text?.trim();
  if (text) return text.length > 120 ? `${text.slice(0, 117)}...` : text;
  if (message.type === "image") return "Sent you a photo";
  if (message.type === "voice") return "Sent you a voice message";
  if (message.type === "file" && message.mime_type?.startsWith("video/")) {
    return "Sent you a video";
  }
  if (message.type === "file") return "Sent you a document";
  return "Sent you a message";
}

function assertRecent(value: string | null, label: string) {
  const timestamp = value ? new Date(value).getTime() : Number.NaN;
  if (!Number.isFinite(timestamp) || Date.now() - timestamp > 5 * 60 * 1000) {
    throw new Error(`This ${label} is too old to notify`);
  }
}

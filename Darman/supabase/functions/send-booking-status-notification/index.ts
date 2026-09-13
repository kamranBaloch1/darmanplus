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

    const { booking_id: bookingId } = await request.json();
    if (!bookingId) throw new Error("booking_id is required");

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: booking, error: bookingError } = await admin
      .from("bookings")
      .select("id, patient_id, doctor_id, status, updated_at")
      .eq("id", bookingId)
      .single();

    if (bookingError || !booking) throw new Error("Booking not found");
    if (booking.doctor_id !== user.id) throw new Error("Access denied");
    if (!["accepted", "cancelled"].includes(booking.status)) {
      throw new Error("Booking must be accepted or cancelled");
    }

    const updatedAt = new Date(booking.updated_at).getTime();
    if (!Number.isFinite(updatedAt) || Date.now() - updatedAt > 5 * 60 * 1000) {
      throw new Error("This booking update is too old to notify");
    }

    const { data: doctor } = await admin
      .from("users")
      .select("name")
      .eq("uid", user.id)
      .maybeSingle();

    const doctorName = doctor?.name?.trim() || "Your doctor";
    const accepted = booking.status === "accepted";
    const title = accepted
      ? "Consultation accepted"
      : "Consultation request declined";
    const notificationBody = accepted
      ? `${doctorName} accepted your consultation request`
      : `${doctorName} declined your consultation request`;
    const notificationType = accepted
      ? "consultation_accepted"
      : "consultation_declined";

    const result = await sendPushToUser({
      admin,
      userId: booking.patient_id,
      title,
      body: notificationBody,
      noDevicesMessage: "Patient has no registered device",
      data: {
        type: notificationType,
        booking_id: booking.id,
        doctor_id: booking.doctor_id,
        doctor_name: doctorName,
      },
    });

    return Response.json(
      {
        sent: result.sent,
        attempted: result.attempted,
        message: result.message,
        status: booking.status,
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

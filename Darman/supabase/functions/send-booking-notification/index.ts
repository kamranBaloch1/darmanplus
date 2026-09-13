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

    const {
      data: { user },
      error: authError,
    } = await userClient.auth.getUser();

    if (authError || !user) throw new Error("Authentication required");

    const body = await request.json();
    const bookingId = body.booking_id?.toString();
    if (!bookingId) throw new Error("booking_id is required");

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );

    const { data: booking, error: bookingError } = await admin
      .from("bookings")
      .select("id, patient_id, doctor_id, status, created_at")
      .eq("id", bookingId)
      .single();

    if (bookingError || !booking) throw new Error("Booking not found");
    if (booking.patient_id !== user.id) throw new Error("Access denied");
    if (booking.status !== "pending") {
      throw new Error("Only pending bookings can send this notification");
    }

    const createdAt = new Date(booking.created_at).getTime();
    if (!Number.isFinite(createdAt) || Date.now() - createdAt > 5 * 60 * 1000) {
      throw new Error("This booking notification is no longer available");
    }

    const { data: patient } = await admin
      .from("users")
      .select("name")
      .eq("uid", booking.patient_id)
      .maybeSingle();

    const patientName = patient?.name?.trim() || "A patient";
    const result = await sendPushToUser({
      admin,
      userId: booking.doctor_id,
      title: "New consultation request",
      body: `${patientName} requested a consultation`,
      noDevicesMessage: "Doctor has no registered device",
      data: {
        type: "consultation_request",
        booking_id: booking.id,
        patient_id: booking.patient_id,
        patient_name: patientName,
      },
    });

    return Response.json(
      {
        sent: result.sent,
        attempted: result.attempted,
        message: result.message,
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

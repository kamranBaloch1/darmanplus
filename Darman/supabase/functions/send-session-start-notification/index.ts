import { createClient } from "npm:@supabase/supabase-js@2";
import { sendPushToUser } from "../_shared/push.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
};

type SessionEvent = "requested" | "accepted" | "declined";

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
    const bookingId = body.booking_id?.toString();
    const event = body.event?.toString() as SessionEvent;
    if (!bookingId) throw new Error("booking_id is required");
    if (!["requested", "accepted", "declined"].includes(event)) {
      throw new Error("Unsupported session event");
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: booking, error: bookingError } = await admin
      .from("bookings")
      .select(
        "id, patient_id, doctor_id, status, session_start_status, session_start_requested_at, session_start_responded_at",
      )
      .eq("id", bookingId)
      .single();
    if (bookingError || !booking) throw new Error("Booking not found");

    let recipientId: string;
    let title: string;
    let notificationBody: string;
    let notificationType: string;

    const [{ data: doctor }, { data: patient }] = await Promise.all([
      admin.from("users").select("name").eq("uid", booking.doctor_id)
        .maybeSingle(),
      admin.from("users").select("name").eq("uid", booking.patient_id)
        .maybeSingle(),
    ]);
    const doctorName = doctor?.name?.trim() || "Your doctor";
    const patientName = patient?.name?.trim() || "The patient";

    if (event === "requested") {
      if (user.id !== booking.doctor_id) throw new Error("Access denied");
      if (
        booking.status !== "accepted" ||
        booking.session_start_status !== "pending"
      ) {
        throw new Error("There is no active consultation-start request");
      }
      assertRecent(booking.session_start_requested_at);
      recipientId = booking.patient_id;
      title = "Doctor is ready to start";
      notificationBody =
        `${doctorName} requested to start your consultation. Open Darmaan to respond.`;
      notificationType = "session_start_requested";
    } else {
      if (user.id !== booking.patient_id) throw new Error("Access denied");
      assertRecent(booking.session_start_responded_at);
      recipientId = booking.doctor_id;
      if (event === "accepted") {
        if (booking.status !== "inProgress") {
          throw new Error("The consultation has not been accepted");
        }
        title = "Consultation start accepted";
        notificationBody =
          `${patientName} accepted your request. The consultation is now active.`;
        notificationType = "session_start_accepted";
      } else {
        if (booking.session_start_status !== "declined") {
          throw new Error("The consultation-start request was not declined");
        }
        title = "Consultation start declined";
        notificationBody =
          `${patientName} is not ready to start the consultation yet.`;
        notificationType = "session_start_declined";
      }
    }

    const result = await sendPushToUser({
      admin,
      userId: recipientId,
      title,
      body: notificationBody,
      data: {
        type: notificationType,
        booking_id: booking.id,
        doctor_id: booking.doctor_id,
        patient_id: booking.patient_id,
        doctor_name: doctorName,
        patient_name: patientName,
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

function assertRecent(value: string | null) {
  const timestamp = value ? new Date(value).getTime() : Number.NaN;
  if (!Number.isFinite(timestamp) || Date.now() - timestamp > 5 * 60 * 1000) {
    throw new Error("This consultation update is too old to notify");
  }
}

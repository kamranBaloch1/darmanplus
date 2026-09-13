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
    const bookingId = body.booking_id?.toString().trim() ?? "";
    if (!bookingId) throw new Error("booking_id is required");

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: booking, error: bookingError } = await admin
      .from("bookings")
      .select(
        "id, patient_id, doctor_id, status, follow_up_date, follow_up_ended_at",
      )
      .eq("id", bookingId)
      .single();
    if (bookingError || !booking) throw new Error("Booking not found");
    if (user.id !== booking.doctor_id) throw new Error("Access denied");
    if (booking.status !== "completed" || !booking.follow_up_ended_at) {
      throw new Error("The follow-up has not ended");
    }
    assertRecent(booking.follow_up_ended_at);

    const [{ data: doctor }, { data: patient }] = await Promise.all([
      admin.from("users").select("name").eq("uid", booking.doctor_id)
        .maybeSingle(),
      admin.from("users").select("name").eq("uid", booking.patient_id)
        .maybeSingle(),
    ]);
    const doctorName = doctor?.name?.trim() || "Your doctor";
    const patientName = patient?.name?.trim() || "Your patient";

    const recipients = [
      {
        userId: booking.patient_id,
        recipientType: "patient",
        title: "Follow-up ended",
        notificationBody:
          `Your follow-up session with ${doctorName} has ended.`,
      },
      {
        userId: booking.doctor_id,
        recipientType: "doctor",
        title: "Follow-up ended",
        notificationBody:
          `Your follow-up session with ${patientName} has ended.`,
      },
    ];

    let sent = 0;
    let attempted = 0;
    for (const recipient of recipients) {
      const result = await sendPushToUser({
        admin,
        userId: recipient.userId,
        title: recipient.title,
        body: recipient.notificationBody,
        ttl: "86400s",
        data: {
          type: "consultation_follow_up_ended",
          recipient_type: recipient.recipientType,
          booking_id: booking.id,
          doctor_id: booking.doctor_id,
          patient_id: booking.patient_id,
          doctor_name: doctorName,
          patient_name: patientName,
          follow_up_date: booking.follow_up_date ?? "",
        },
      });
      sent += result.sent;
      attempted += result.attempted;
    }

    return Response.json({ sent, attempted }, { headers: corsHeaders });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Notification failed" },
      { status: 400, headers: corsHeaders },
    );
  }
});

function assertRecent(value: string) {
  const timestamp = new Date(value).getTime();
  if (!Number.isFinite(timestamp) || Date.now() - timestamp > 5 * 60 * 1000) {
    throw new Error("This follow-up update is too old to notify");
  }
}

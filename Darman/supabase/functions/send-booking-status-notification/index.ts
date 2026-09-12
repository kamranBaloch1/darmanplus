import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

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

    const [{ data: doctor }, { data: devices, error: tokenError }] =
      await Promise.all([
        admin.from("users").select("name").eq("uid", user.id).maybeSingle(),
        admin
          .from("push_notification_tokens")
          .select("token")
          .eq("user_id", booking.patient_id),
      ]);

    if (tokenError) throw tokenError;
    if (!devices?.length) {
      return Response.json(
        { sent: 0, message: "Patient has no registered device" },
        { headers: corsHeaders },
      );
    }

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

    const credentialsJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!credentialsJson) throw new Error("Firebase is not configured");
    const credentials = JSON.parse(credentialsJson);

    const googleAuth = new GoogleAuth({
      credentials,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });
    const authClient = await googleAuth.getClient();
    const accessTokenResult = await authClient.getAccessToken();
    const accessToken = typeof accessTokenResult === "string"
      ? accessTokenResult
      : accessTokenResult.token;
    if (!accessToken) throw new Error("Firebase authorization failed");

    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;

    const results = await Promise.all(devices.map(async ({ token }) => {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            notification: { title, body: notificationBody },
            data: {
              type: notificationType,
              booking_id: booking.id,
              doctor_id: booking.doctor_id,
              doctor_name: doctorName,
            },
            android: {
              priority: "HIGH",
              ttl: "3600s",
              notification: {
                channel_id: "consultation_requests",
                sound: "default",
                visibility: "PRIVATE",
                notification_priority: "PRIORITY_HIGH",
                default_vibrate_timings: true,
              },
            },
            apns: {
              headers: { "apns-priority": "10" },
              payload: { aps: { sound: "default", badge: 1 } },
            },
          },
        }),
      });

      if (response.ok) return { sent: true };
      const errorBody = await response.text();
      if (errorBody.includes("UNREGISTERED")) {
        await admin.from("push_notification_tokens").delete().eq("token", token);
      }
      return { sent: false, error: errorBody };
    }));

    return Response.json(
      {
        sent: results.filter((result) => result.sent).length,
        attempted: results.length,
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
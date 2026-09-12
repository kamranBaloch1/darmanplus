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

    const [{ data: patient }, { data: devices, error: deviceError }] =
      await Promise.all([
        admin
          .from("users")
          .select("name")
          .eq("uid", booking.patient_id)
          .maybeSingle(),
        admin
          .from("push_notification_tokens")
          .select("token")
          .eq("user_id", booking.doctor_id),
      ]);

    if (deviceError) throw deviceError;
    if (!devices?.length) {
      return Response.json(
        { sent: 0, message: "Doctor has no registered device" },
        { headers: corsHeaders },
      );
    }

    const patientName = patient?.name?.trim() || "A patient";
    const serviceAccountJson = Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON");
    if (!serviceAccountJson) {
      throw new Error("Firebase service account is not configured");
    }

    const serviceAccount = JSON.parse(serviceAccountJson);
    const auth = new GoogleAuth({
      credentials: serviceAccount,
      scopes: ["https://www.googleapis.com/auth/firebase.messaging"],
    });

    const authClient = await auth.getClient();
    const accessTokenResult = await authClient.getAccessToken();
    const accessToken = typeof accessTokenResult === "string"
      ? accessTokenResult
      : accessTokenResult.token;

    if (!accessToken) throw new Error("Unable to authorize Firebase request");

    const endpoint =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

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
            notification: {
              title: "New consultation request",
              body: `${patientName} requested a consultation`,
            },
            data: {
              type: "consultation_request",
              booking_id: booking.id,
              patient_id: booking.patient_id,
              patient_name: patientName,
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
              payload: {
                aps: { sound: "default", badge: 1 },
              },
            },
          },
        }),
      });

      if (response.ok) return { sent: true };

      const errorBody = await response.text();
      if (errorBody.includes("UNREGISTERED")) {
        await admin
          .from("push_notification_tokens")
          .delete()
          .eq("token", token);
      }

      return { sent: false, error: errorBody };
    }));

    return Response.json(
      {
        sent: results.filter((result) => result.sent).length,
        attempted: results.length,
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

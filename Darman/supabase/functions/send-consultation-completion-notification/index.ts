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
    const { data: { user }, error: authError } =
      await userClient.auth.getUser();
    if (authError || !user) throw new Error("Authentication required");

    const requestBody = await request.json();
    const bookingId = requestBody.booking_id?.toString();
    const event = requestBody.event?.toString();
    if (!bookingId) throw new Error("booking_id is required");
    if (
      event !== "ended" && event !== "rated" &&
      event !== "follow_up_scheduled"
    ) {
      throw new Error("Unsupported completion event");
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: booking, error: bookingError } = await admin
      .from("bookings")
      .select(
        "id, patient_id, doctor_id, status, completed_at, follow_up_date, follow_up_scheduled_at",
      )
      .eq("id", bookingId)
      .single();
    if (bookingError || !booking) throw new Error("Booking not found");
    if (booking.status !== "completed") {
      throw new Error("The consultation is not completed");
    }

    const [{ data: doctor }, { data: patient }] = await Promise.all([
      admin.from("users").select("name").eq("uid", booking.doctor_id)
        .maybeSingle(),
      admin.from("users").select("name").eq("uid", booking.patient_id)
        .maybeSingle(),
    ]);
    const doctorName = doctor?.name?.trim() || "Your doctor";
    const patientName = patient?.name?.trim() || "A patient";

    let recipientId: string;
    let title: string;
    let notificationBody: string;
    let notificationType: string;
    let ratingValue = "";

    if (event === "ended") {
      if (user.id !== booking.doctor_id) throw new Error("Access denied");
      assertRecent(booking.completed_at, "completion");
      recipientId = booking.patient_id;
      title = "Consultation completed";
      notificationBody =
        `${doctorName} ended the consultation. View your receipt and rate the doctor.`;
      notificationType = "consultation_completed";
    } else if (event === "follow_up_scheduled") {
      if (user.id !== booking.doctor_id) throw new Error("Access denied");
      if (!booking.follow_up_date) throw new Error("Follow-up not found");
      assertRecent(booking.follow_up_scheduled_at, "follow-up");
      const formattedDate = new Intl.DateTimeFormat("en-PK", {
        day: "numeric",
        month: "short",
        year: "numeric",
        timeZone: "Asia/Karachi",
      }).format(new Date(`${booking.follow_up_date}T12:00:00+05:00`));
      recipientId = booking.patient_id;
      title = "Follow-up scheduled";
      notificationBody =
        `${doctorName} scheduled your free follow-up for ${formattedDate}.`;
      notificationType = "consultation_follow_up";
    } else {
      if (user.id !== booking.patient_id) throw new Error("Access denied");
      const { data: rating, error: ratingError } = await admin
        .from("consultation_ratings")
        .select("rating, updated_at")
        .eq("booking_id", booking.id)
        .eq("patient_id", booking.patient_id)
        .eq("doctor_id", booking.doctor_id)
        .single();
      if (ratingError || !rating) throw new Error("Rating not found");
      assertRecent(rating.updated_at, "rating");
      ratingValue = String(rating.rating);
      recipientId = booking.doctor_id;
      title = "New patient rating";
      notificationBody =
        `${patientName} rated you ${rating.rating} ${rating.rating === 1 ? "star" : "stars"}.`;
      notificationType = "consultation_rated";
    }

    const { data: devices, error: tokenError } = await admin
      .from("push_notification_tokens")
      .select("token")
      .eq("user_id", recipientId);
    if (tokenError) throw tokenError;
    if (!devices?.length) {
      return Response.json(
        { sent: 0, message: "Recipient has no registered device" },
        { headers: corsHeaders },
      );
    }

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
              patient_id: booking.patient_id,
              doctor_name: doctorName,
              patient_name: patientName,
              rating: ratingValue,
              follow_up_date: booking.follow_up_date ?? "",
            },
            android: {
              priority: "HIGH",
              ttl: "86400s",
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
        await admin.from("push_notification_tokens").delete().eq(
          "token",
          token,
        );
      }
      return { sent: false, error: errorBody };
    }));

    return Response.json(
      {
        sent: results.filter((result) => result.sent).length,
        attempted: results.length,
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

function assertRecent(value: string | null, label: string) {
  const timestamp = value ? new Date(value).getTime() : Number.NaN;
  if (!Number.isFinite(timestamp) || Date.now() - timestamp > 5 * 60 * 1000) {
    throw new Error(`This ${label} update is too old to notify`);
  }
}

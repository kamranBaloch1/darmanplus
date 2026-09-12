import { createClient } from "npm:@supabase/supabase-js@2";
import { GoogleAuth } from "npm:google-auth-library@9";

type CallInvite = {
  id: string;
  booking_id: string;
  caller_id: string;
  caller_name: string;
  caller_is_doctor: boolean;
  callee_id: string;
  status: string;
  expires_at: string;
};

type WebhookPayload = {
  type: "INSERT" | "UPDATE" | "DELETE";
  table: string;
  schema: string;
  record: CallInvite;
  old_record: CallInvite | null;
};

Deno.serve(async (request) => {
  try {
    if (request.method === "OPTIONS") {
      return new Response("ok", {
        headers: {
          "Access-Control-Allow-Origin": "*",
          "Access-Control-Allow-Headers":
            "authorization, x-client-info, apikey, content-type, x-webhook-secret",
        },
      });
    }
    if (request.method !== "POST") {
      return Response.json({ error: "Method not allowed" }, { status: 405 });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const expectedSecret = Deno.env.get("CALL_NOTIFICATION_WEBHOOK_SECRET");
    const receivedSecret = request.headers.get("x-webhook-secret");
    let invite: CallInvite;

    if (expectedSecret && receivedSecret === expectedSecret) {
      const payload = await request.json() as WebhookPayload;
      if (
        payload.type !== "INSERT" ||
        payload.table !== "consultation_call_invites"
      ) {
        return Response.json({ sent: 0, skipped: true });
      }
      invite = payload.record;
    } else {
      const authorization = request.headers.get("Authorization");
      if (!authorization) {
        return Response.json({ error: "Unauthorized" }, { status: 401 });
      }
      const userClient = createClient(
        Deno.env.get("SUPABASE_URL")!,
        Deno.env.get("SUPABASE_ANON_KEY")!,
        { global: { headers: { Authorization: authorization } } },
      );
      const { data: { user }, error: authError } =
        await userClient.auth.getUser();
      if (authError || !user) {
        return Response.json({ error: "Unauthorized" }, { status: 401 });
      }
      const body = await request.json();
      const inviteId = body.invite_id?.toString();
      if (!inviteId) {
        return Response.json({ error: "invite_id is required" }, { status: 400 });
      }
      const { data, error } = await supabase
        .from("consultation_call_invites")
        .select(
          "id, booking_id, caller_id, caller_name, caller_is_doctor, callee_id, status, expires_at",
        )
        .eq("id", inviteId)
        .single();
      if (error || !data) {
        return Response.json({ error: "Call request not found" }, { status: 404 });
      }
      if (data.caller_id !== user.id) {
        return Response.json({ error: "Access denied" }, { status: 403 });
      }
      invite = data as CallInvite;
    }

    const isRinging = invite.status === "ringing" &&
      new Date(invite.expires_at).getTime() > Date.now();

    const { data: callerProfile } = await supabase
      .from("users")
      .select(
        "name, role, profile_image, is_doctor_verified, specialization, title",
      )
      .eq("uid", invite.caller_id)
      .maybeSingle();
    const savedCallerName = callerProfile?.name?.toString().trim();
    const callerIsDoctor = callerProfile?.role === "doctor" ||
      invite.caller_is_doctor;
    const callerName = savedCallerName || (callerIsDoctor ? "Doctor" : "Patient");
    const callerVerified = callerIsDoctor &&
      callerProfile?.is_doctor_verified === true;
    const callerSubtitle = [callerProfile?.specialization, callerProfile?.title]
      .map((value) => value?.toString().trim() ?? "")
      .filter((value) => value.length > 0)
      .join(" | ");

    const { data: devices, error: deviceError } = await supabase
      .from("push_notification_tokens")
      .select("token, platform")
      .eq("user_id", invite.callee_id);

    if (deviceError) throw deviceError;
    if (!devices?.length) return Response.json({ sent: 0 });

    const serviceAccount = JSON.parse(
      Deno.env.get("FIREBASE_SERVICE_ACCOUNT_JSON")!,
    );

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

    const title = isRinging
      ? `Video call from ${callerName}`
      : "Video call ended";
    const body = isRinging
      ? `${callerName} is calling you.`
      : `The call from ${callerName} has ended.`;
    const notificationType = isRinging
      ? "incoming_video_call"
      : "incoming_video_call_ended";

    const results = await Promise.all(devices.map(async ({ token, platform }) => {
      const data = {
        type: notificationType,
        invite_id: invite.id,
        booking_id: invite.booking_id,
        caller_name: callerName,
        caller_avatar: callerProfile?.profile_image?.toString() ?? "",
        caller_verified: callerVerified.toString(),
        caller_subtitle: callerSubtitle,
        title,
        body,
      };
      const isIos = platform === "ios";
      const response = await fetch(endpoint, {
        method: "POST",
        headers: {
          "Authorization": `Bearer ${accessToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token,
            data,
            ...(isIos
              ? {
                ...(isRinging ? { notification: { title, body } } : {}),
                apns: {
                  headers: isRinging
                    ? {
                      "apns-priority": "10",
                      "apns-push-type": "alert",
                      "apns-expiration": String(
                        Math.floor(
                          new Date(invite.expires_at).getTime() / 1000,
                        ),
                      ),
                    }
                    : {
                      "apns-priority": "5",
                      "apns-push-type": "background",
                    },
                  payload: {
                    aps: isRinging
                      ? { sound: "default", badge: 1 }
                      : { "content-available": 1 },
                  },
                },
              }
              : {
                // Data-only delivery is required so Flutter can create the
                // full-screen CATEGORY_CALL notification while backgrounded.
                android: {
                  priority: "HIGH",
                  ttl: isRinging ? "3600s" : "60s",
                },
              }),
          },
        }),
      });

      if (response.ok) return { token, sent: true };

      const errorBody = await response.text();
      if (errorBody.includes("UNREGISTERED")) {
        await supabase
          .from("push_notification_tokens")
          .delete()
          .eq("token", token);
      }

      return { token, sent: false, error: errorBody };
    }));

    return Response.json({
      sent: results.filter((result) => result.sent).length,
      attempted: results.length,
    });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Notification failed" },
      { status: 500 },
    );
  }
});

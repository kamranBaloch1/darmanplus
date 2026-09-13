import { GoogleAuth } from "npm:google-auth-library@9";

type PushDevice = { token: string };

type SendPushOptions = {
  admin: any;
  userId: string;
  title: string;
  body: string;
  data: Record<string, string>;
  channelId?: string;
  ttl?: string;
  sound?: string;
  iosSound?: string;
  noDevicesMessage?: string;
};

type SendPushResult = {
  sent: number;
  attempted: number;
  message?: string;
};

let cachedEndpoint = "";
let cachedAccessToken = "";
let cachedTokenExpiresAt = 0;

async function getFirebaseSender() {
  const now = Date.now();
  if (cachedEndpoint && cachedAccessToken && now < cachedTokenExpiresAt) {
    return { endpoint: cachedEndpoint, accessToken: cachedAccessToken };
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

  cachedEndpoint =
    `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
  cachedAccessToken = accessToken;
  cachedTokenExpiresAt = now + 45 * 60 * 1000;

  return { endpoint: cachedEndpoint, accessToken: cachedAccessToken };
}

export async function sendPushToUser({
  admin,
  userId,
  title,
  body,
  data,
  channelId = "consultation_requests_v2",
  ttl = "3600s",
  sound = "darman_notification",
  iosSound = "darman_notification.caf",
  noDevicesMessage = "Recipient has no registered device",
}: SendPushOptions): Promise<SendPushResult> {
  const { data: devices, error: tokenError } = await admin
    .from("push_notification_tokens")
    .select("token")
    .eq("user_id", userId);

  if (tokenError) throw tokenError;
  if (!devices?.length) {
    return { sent: 0, attempted: 0, message: noDevicesMessage };
  }

  return sendPushToDevices({
    admin,
    devices,
    title,
    body,
    data,
    channelId,
    ttl,
    sound,
    iosSound,
  });
}

async function sendPushToDevices({
  admin,
  devices,
  title,
  body,
  data,
  channelId,
  ttl,
  sound,
  iosSound,
}: {
  admin: any;
  devices: PushDevice[];
  title: string;
  body: string;
  data: Record<string, string>;
  channelId: string;
  ttl: string;
  sound: string;
  iosSound: string;
}): Promise<SendPushResult> {
  const { endpoint, accessToken } = await getFirebaseSender();
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
          notification: { title, body },
          data,
          android: {
            priority: "HIGH",
            ttl,
            notification: {
              channel_id: channelId,
              sound,
              visibility: "PRIVATE",
              notification_priority: "PRIORITY_HIGH",
              default_vibrate_timings: true,
            },
          },
          apns: {
            headers: { "apns-priority": "10" },
            payload: { aps: { sound: iosSound, badge: 1 } },
          },
        },
      }),
    });

    if (response.ok) return true;

    const errorBody = await response.text();
    if (errorBody.includes("UNREGISTERED")) {
      await admin.from("push_notification_tokens").delete().eq("token", token);
    }
    return false;
  }));

  return {
    sent: results.filter(Boolean).length,
    attempted: results.length,
  };
}

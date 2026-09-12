import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const PLAY_TEST_PHONES = new Set([
  "+923000000000", // Doctor test account
  "+923000000001", // Patient test account
]);

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

function normalizePhone(value: string): string {
  let phone = value.replace(/[\s()-]/g, "");
  if (phone.startsWith("03")) phone = `+92${phone.slice(1)}`;
  else if (/^3\d{9}$/.test(phone)) phone = `+92${phone}`;
  else if (phone.startsWith("92")) phone = `+${phone}`;
  if (!/^\+923\d{9}$/.test(phone)) throw new Error("invalid_phone_format");
  return phone;
}

async function hash(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value);
  const digest = await crypto.subtle.digest("SHA-256", bytes);
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

async function consumeLimit(
  admin: ReturnType<typeof createClient>,
  key: string,
  limit: number,
  windowSeconds: number,
): Promise<boolean> {
  const { data, error } = await admin.rpc("consume_phone_otp_rate_limit", {
    p_key: key,
    p_limit: limit,
    p_window_seconds: windowSeconds,
  });
  if (error) throw error;
  return data === true;
}

serve(async (request) => {
  if (request.method !== "POST")
    return json({ error: "method_not_allowed" }, 405);

  let body: { phone?: unknown };
  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }
  if (typeof body.phone !== "string")
    return json({ error: "phone_required" }, 400);

  let phone: string;
  try {
    phone = normalizePhone(body.phone);
  } catch {
    return json({ error: "invalid_phone_format" }, 400);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  if (!supabaseUrl || !serviceRoleKey)
    return json({ error: "server_misconfigured" }, 500);

  try {
    const admin = createClient(supabaseUrl, serviceRoleKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    });
    const clientIp =
      request.headers.get("cf-connecting-ip") ??
      request.headers.get("x-real-ip") ??
      request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown";
    const [phoneHash, ipHash] = await Promise.all([
      hash(`send:phone:${phone}`),
      hash(`send:ip:${clientIp}`),
    ]);
    const [phoneAllowed, ipAllowed] = await Promise.all([
      consumeLimit(admin, `send_phone_${phoneHash}`, 5, 3600),
      consumeLimit(admin, `send_ip_${ipHash}`, 12, 600),
    ]);
    if (!phoneAllowed || !ipAllowed) {
      return json({ error: "max_attempts_reached" }, 429);
    }

    // Google Play reviewers use a fixed, isolated doctor account. Do not send
    // a real WhatsApp message for this number; verification remains server-side
    // and is still protected by the rate limits above.
    if (PLAY_TEST_PHONES.has(phone)) {
      return json({ success: true });
    }

    const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID")?.trim();
    const authToken = Deno.env.get("TWILIO_AUTH_TOKEN")?.trim();
    const serviceSid = Deno.env.get("TWILIO_VERIFY_SERVICE_SID")?.trim();
    if (!accountSid || !authToken || !serviceSid) {
      return json({ error: "server_misconfigured" }, 500);
    }

    const response = await fetch(
      `https://verify.twilio.com/v2/Services/${serviceSid}/Verifications`,
      {
        method: "POST",
        headers: {
          Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
          "Content-Type": "application/x-www-form-urlencoded",
        },
        body: new URLSearchParams({ To: phone, Channel: "whatsapp" }),
      },
    );
    const data = await response.json();
    if (response.ok) return json({ success: true });
    console.error("[send-whatsapp-otp] Twilio rejected request", {
      status: response.status,
      code: data?.code ?? null,
      message: data?.message ?? null,
    });
    if (data?.code === 60203)
      return json({ error: "max_attempts_reached" }, 429);
    if (data?.code === 21211 || data?.code === 60200)
      return json({ error: "invalid_phone_format" }, 400);
    if (
      data?.code === 60205 ||
      data?.message?.toLowerCase().includes("whatsapp")
    ) {
      return json({ error: "phone_not_registered_whatsapp" }, 400);
    }
    return json({ error: "otp_send_failed" }, 400);
  } catch (error) {
    console.error("send-whatsapp-otp", error);
    return json({ error: "internal_server_error" }, 500);
  }
});

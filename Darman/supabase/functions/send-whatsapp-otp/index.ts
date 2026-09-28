import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const PLAY_TEST_PHONES = new Set([
  "+923000000000", // Doctor test account (Pakistan)
  "+923000000001", // Patient test account (Pakistan)
]);

const OTP_EXPIRY_MINUTES = 5;
const RESEND_COOLDOWN_SECONDS = 60;

// ------------------------------------------------------------
// Per-country phone validation.
// Each pattern matches the FULL E.164 number (dial code + national
// number). Mirrors the rules in the Flutter app's country picker.
// This block MUST be identical in send-whatsapp-otp and
// verify-whatsapp-otp, because the phone string is part of the OTP hash.
// ------------------------------------------------------------
const PHONE_PATTERNS: Record<string, RegExp> = {
  // ---- Original countries (unchanged) ----
  PK: /^\+923\d{9}$/, // +92 3XXXXXXXXX
  AE: /^\+9715\d{8}$/, // +971 5XXXXXXXX
  SA: /^\+9665\d{8}$/, // +966 5XXXXXXXX
  OM: /^\+968\d{8}$/, // +968 XXXXXXXX
  BH: /^\+973\d{8}$/, // +973 XXXXXXXX
  QA: /^\+974\d{8}$/, // +974 XXXXXXXX
  IR: /^\+989\d{9}$/, // +98 9XXXXXXXXX
  AF: /^\+937\d{8}$/, // +93 7XXXXXXXX
  US: /^\+1\d{10}$/, // +1 XXXXXXXXXX
  CA: /^\+1\d{10}$/, // +1 XXXXXXXXXX
  DE: /^\+49\d{10,11}$/, // +49 X{10,11}
  NL: /^\+316\d{8}$/, // +31 6XXXXXXXX
  IT: /^\+393\d{9}$/, // +39 3XXXXXXXXX

  // ---- All other countries (generated from libphonenumber; length only) ----
  AC: /^\+247\d{5}$/,
  AD: /^\+376\d{6,9}$/,
  AG: /^\+1\d{10}$/,
  AL: /^\+355\d{9}$/,
  AM: /^\+374\d{8}$/,
  AO: /^\+244\d{9}$/,
  AR: /^\+54\d{10,11}$/,
  AT: /^\+43\d{7,13}$/,
  AU: /^\+61\d{9}$/,
  AW: /^\+297\d{7}$/,
  AX: /^\+358\d{6,10}$/,
  AZ: /^\+994\d{9}$/,
  BA: /^\+387\d{8,9}$/,
  BD: /^\+880\d{10}$/,
  BE: /^\+32\d{9}$/,
  BF: /^\+226\d{8}$/,
  BG: /^\+359\d{8,9}$/,
  BI: /^\+257\d{8}$/,
  BJ: /^\+229\d{10}$/,
  BL: /^\+590\d{9}$/,
  BN: /^\+673\d{7}$/,
  BO: /^\+591\d{8}$/,
  BQ: /^\+599\d{7}$/,
  BR: /^\+55\d{10,11}$/,
  BT: /^\+975\d{8}$/,
  BW: /^\+267\d{8}$/,
  BY: /^\+375\d{9}$/,
  BZ: /^\+501\d{7}$/,
  CD: /^\+243\d{7,9}$/,
  CF: /^\+236\d{8}$/,
  CG: /^\+242\d{9}$/,
  CH: /^\+41\d{9}$/,
  CI: /^\+225\d{10}$/,
  CK: /^\+682\d{5}$/,
  CL: /^\+56\d{9}$/,
  CM: /^\+237\d{9}$/,
  CN: /^\+86\d{11}$/,
  CO: /^\+57\d{10}$/,
  CR: /^\+506\d{8}$/,
  CU: /^\+53\d{8}$/,
  CV: /^\+238\d{7}$/,
  CW: /^\+599\d{7,8}$/,
  CY: /^\+357\d{8}$/,
  CZ: /^\+420\d{9}$/,
  DJ: /^\+253\d{8}$/,
  DK: /^\+45\d{8}$/,
  DZ: /^\+213\d{9}$/,
  EC: /^\+593\d{9}$/,
  EE: /^\+372\d{7,8}$/,
  EG: /^\+20\d{10}$/,
  EH: /^\+212\d{9}$/,
  ER: /^\+291\d{7}$/,
  ES: /^\+34\d{9}$/,
  ET: /^\+251\d{9}$/,
  FJ: /^\+679\d{7}$/,
  FK: /^\+500\d{5}$/,
  FM: /^\+691\d{7}$/,
  FO: /^\+298\d{6}$/,
  FR: /^\+33\d{9}$/,
  GA: /^\+241\d{7,8}$/,
  GB: /^\+44\d{10}$/,
  GE: /^\+995\d{9}$/,
  GF: /^\+594\d{9}$/,
  GH: /^\+233\d{9}$/,
  GI: /^\+350\d{8}$/,
  GL: /^\+299\d{6}$/,
  GM: /^\+220\d{7,9}$/,
  GN: /^\+224\d{9}$/,
  GQ: /^\+240\d{9}$/,
  GR: /^\+30\d{10}$/,
  GT: /^\+502\d{8}$/,
  GW: /^\+245\d{9}$/,
  GY: /^\+592\d{7}$/,
  HK: /^\+852\d{8}$/,
  HN: /^\+504\d{8}$/,
  HR: /^\+385\d{8,9}$/,
  HT: /^\+509\d{8}$/,
  HU: /^\+36\d{9}$/,
  ID: /^\+62\d{9,12}$/,
  IE: /^\+353\d{9}$/,
  IL: /^\+972\d{9}$/,
  IN: /^\+91\d{10}$/,
  IO: /^\+246\d{7}$/,
  IQ: /^\+964\d{10}$/,
  IS: /^\+354\d{7,9}$/,
  JO: /^\+962\d{9}$/,
  JP: /^\+81\d{10}$/,
  KE: /^\+254\d{9}$/,
  KG: /^\+996\d{9}$/,
  KH: /^\+855\d{8,9}$/,
  KI: /^\+686\d{8}$/,
  KM: /^\+269\d{7}$/,
  KP: /^\+850\d{10}$/,
  KR: /^\+82\d{9,10}$/,
  KW: /^\+965\d{8}$/,
  KZ: /^\+7\d{10}$/,
  LA: /^\+856\d{9,10}$/,
  LB: /^\+961\d{7,8}$/,
  LI: /^\+423\d{7,9}$/,
  LK: /^\+94\d{9}$/,
  LR: /^\+231\d{7,9}$/,
  LS: /^\+266\d{8}$/,
  LT: /^\+370\d{8}$/,
  LU: /^\+352\d{9}$/,
  LV: /^\+371\d{8}$/,
  LY: /^\+218\d{9}$/,
  MC: /^\+377\d{8,9}$/,
  MD: /^\+373\d{8}$/,
  ME: /^\+382\d{8}$/,
  MG: /^\+261\d{9}$/,
  MH: /^\+692\d{7}$/,
  MK: /^\+389\d{8}$/,
  ML: /^\+223\d{8}$/,
  MM: /^\+95\d{7,10}$/,
  MN: /^\+976\d{8}$/,
  MO: /^\+853\d{8}$/,
  MQ: /^\+596\d{9}$/,
  MR: /^\+222\d{8}$/,
  MT: /^\+356\d{8}$/,
  MU: /^\+230\d{8}$/,
  MV: /^\+960\d{7}$/,
  MW: /^\+265\d{9}$/,
  MX: /^\+52\d{10}$/,
  MY: /^\+60\d{9,10}$/,
  MZ: /^\+258\d{9}$/,
  NA: /^\+264\d{9}$/,
  NC: /^\+687\d{6}$/,
  NE: /^\+227\d{8}$/,
  NF: /^\+672\d{6}$/,
  NG: /^\+234\d{10}$/,
  NI: /^\+505\d{8}$/,
  NO: /^\+47\d{8}$/,
  NP: /^\+977\d{10}$/,
  NR: /^\+674\d{7}$/,
  NU: /^\+683\d{4,7}$/,
  NZ: /^\+64\d{8,10}$/,
  PA: /^\+507\d{7,8}$/,
  PE: /^\+51\d{9}$/,
  PF: /^\+689\d{8}$/,
  PG: /^\+675\d{8}$/,
  PH: /^\+63\d{10}$/,
  PL: /^\+48\d{9}$/,
  PM: /^\+508\d{6,9}$/,
  PS: /^\+970\d{9}$/,
  PT: /^\+351\d{9}$/,
  PW: /^\+680\d{7}$/,
  PY: /^\+595\d{9}$/,
  RE: /^\+262\d{9}$/,
  RO: /^\+40\d{9}$/,
  RS: /^\+381\d{8,10}$/,
  RW: /^\+250\d{9}$/,
  SB: /^\+677\d{5,7}$/,
  SC: /^\+248\d{7}$/,
  SD: /^\+249\d{9}$/,
  SE: /^\+46\d{9}$/,
  SG: /^\+65\d{8}$/,
  SH: /^\+290\d{5}$/,
  SI: /^\+386\d{8}$/,
  SK: /^\+421\d{9}$/,
  SL: /^\+232\d{8}$/,
  SM: /^\+378\d{8}$/,
  SN: /^\+221\d{9}$/,
  SO: /^\+252\d{7,9}$/,
  SR: /^\+597\d{7}$/,
  SS: /^\+211\d{9}$/,
  ST: /^\+239\d{7}$/,
  SV: /^\+503\d{8}$/,
  SY: /^\+963\d{9}$/,
  SZ: /^\+268\d{8}$/,
  TA: /^\+290\d{4}$/,
  TD: /^\+235\d{8}$/,
  TG: /^\+228\d{8}$/,
  TH: /^\+66\d{9}$/,
  TJ: /^\+992\d{9}$/,
  TK: /^\+690\d{4,7}$/,
  TL: /^\+670\d{8}$/,
  TM: /^\+993\d{8}$/,
  TN: /^\+216\d{8}$/,
  TO: /^\+676\d{7}$/,
  TR: /^\+90\d{10}$/,
  TV: /^\+688\d{6,7}$/,
  TW: /^\+886\d{9}$/,
  TZ: /^\+255\d{9}$/,
  UA: /^\+380\d{9}$/,
  UG: /^\+256\d{9}$/,
  UY: /^\+598\d{8}$/,
  UZ: /^\+998\d{9}$/,
  VA: /^\+39\d{9,10}$/,
  VE: /^\+58\d{10}$/,
  VN: /^\+84\d{9}$/,
  VU: /^\+678\d{7}$/,
  WF: /^\+681\d{6}$/,
  WS: /^\+685\d{7,10}$/,
  XK: /^\+383\d{8}$/,
  YE: /^\+967\d{9}$/,
  ZA: /^\+27\d{5,9}$/,
  ZM: /^\+260\d{9}$/,
  ZW: /^\+263\d{9}$/,
};

function normalizePhone(value: string): string {
  // Strip whitespace/punctuation but keep a leading "+".
  const phone = value.replace(/[\s()-]/g, "");

  // The app sends fully-formed E.164 numbers, so require "+".
  if (!phone.startsWith("+")) {
    throw new Error("invalid_phone_format");
  }

  const isValid = Object.values(PHONE_PATTERNS).some((pattern) =>
    pattern.test(phone)
  );

  if (!isValid) {
    throw new Error("invalid_phone_format");
  }

  return phone;
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
    },
  });

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
  const { data, error } = await admin.rpc(
    "consume_phone_otp_rate_limit",
    {
      p_key: key,
      p_limit: limit,
      p_window_seconds: windowSeconds,
    },
  );

  if (error) {
    throw error;
  }

  return data === true;
}

function generateOtp(): string {
  const array = new Uint32Array(1);

  crypto.getRandomValues(array);

  return String(array[0] % 1000000).padStart(6, "0");
}

serve(async (request) => {
  // ------------------------------------------------------------
  // Method
  // ------------------------------------------------------------

  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  // ------------------------------------------------------------
  // Parse request
  // ------------------------------------------------------------

  let body: { phone?: unknown };

  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (typeof body.phone !== "string") {
    return json({ error: "phone_required" }, 400);
  }

  // ------------------------------------------------------------
  // Normalize phone
  // ------------------------------------------------------------

  let phone: string;

  try {
    phone = normalizePhone(body.phone);
  } catch {
    return json({ error: "invalid_phone_format" }, 400);
  }

  // ------------------------------------------------------------
  // Environment variables
  // ------------------------------------------------------------

  const supabaseUrl = Deno.env.get("SUPABASE_URL")?.trim();
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();
  const metaAccessToken = Deno.env.get("META_WHATSAPP_ACCESS_TOKEN")?.trim();
  const metaPhoneNumberId = Deno.env
    .get("META_WHATSAPP_PHONE_NUMBER_ID")
    ?.trim();
  const metaApiVersion =
    Deno.env.get("META_WHATSAPP_API_VERSION")?.trim() || "v25.0";
  const metaTemplateName = Deno.env.get("META_OTP_TEMPLATE_NAME")?.trim();
  const metaTemplateLanguage =
    Deno.env.get("META_OTP_TEMPLATE_LANGUAGE")?.trim() || "en";

  // ------------------------------------------------------------
  // Configuration check
  // ------------------------------------------------------------

  const missingConfig: string[] = [];

  if (!supabaseUrl) missingConfig.push("SUPABASE_URL");
  if (!serviceRoleKey) missingConfig.push("SUPABASE_SERVICE_ROLE_KEY");
  if (!metaAccessToken) missingConfig.push("META_WHATSAPP_ACCESS_TOKEN");
  if (!metaPhoneNumberId) missingConfig.push("META_WHATSAPP_PHONE_NUMBER_ID");
  if (!metaTemplateName) missingConfig.push("META_OTP_TEMPLATE_NAME");

  if (missingConfig.length > 0) {
    console.error(
      "[send-whatsapp-otp] Missing configuration",
      missingConfig,
    );

    return json(
      {
        error: "server_misconfigured",
        missing: missingConfig,
      },
      500,
    );
  }

  try {
    const admin = createClient(supabaseUrl!, serviceRoleKey!, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // ----------------------------------------------------------
    // Get client IP
    // ----------------------------------------------------------

    const clientIp =
      request.headers.get("cf-connecting-ip") ??
        request.headers.get("x-real-ip") ??
        request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
        "unknown";

    const [phoneHash, ipHash] = await Promise.all([
      hash(`send:phone:${phone}`),
      hash(`send:ip:${clientIp}`),
    ]);

    // ----------------------------------------------------------
    // Rate limits
    //
    // Phone: 5 per hour
    // IP: 12 per 10 minutes
    // ----------------------------------------------------------

    const [phoneAllowed, ipAllowed] = await Promise.all([
      consumeLimit(admin, `send_phone_${phoneHash}`, 5, 3600),
      consumeLimit(admin, `send_ip_${ipHash}`, 12, 600),
    ]);

    if (!phoneAllowed || !ipAllowed) {
      return json({ error: "max_attempts_reached" }, 429);
    }

    // ----------------------------------------------------------
    // Google Play test accounts
    // ----------------------------------------------------------

    if (PLAY_TEST_PHONES.has(phone)) {
      return json({ success: true });
    }

    // ----------------------------------------------------------
    // 60-second resend cooldown
    // ----------------------------------------------------------

    const { data: recentOtp, error: recentOtpError } = await admin
      .from("phone_otp_codes")
      .select("created_at")
      .eq("phone", phone)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (recentOtpError) {
      console.error(
        "[send-whatsapp-otp] Failed to check resend cooldown",
        recentOtpError,
      );

      return json({ error: "internal_server_error" }, 500);
    }

    if (recentOtp?.created_at) {
      const createdAt = new Date(recentOtp.created_at).getTime();
      const elapsedSeconds = (Date.now() - createdAt) / 1000;

      if (elapsedSeconds < RESEND_COOLDOWN_SECONDS) {
        return json(
          {
            error: "resend_too_soon",
            retry_after: Math.ceil(RESEND_COOLDOWN_SECONDS - elapsedSeconds),
          },
          429,
        );
      }
    }

    // ----------------------------------------------------------
    // Generate OTP
    // ----------------------------------------------------------

    const otp = generateOtp();

    const codeHash = await hash(`otp:${phone}:${otp}`);

    const expiresAt = new Date(
      Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000,
    ).toISOString();

    // ----------------------------------------------------------
    // Invalidate previous active OTPs
    // ----------------------------------------------------------

    const { error: invalidateError } = await admin
      .from("phone_otp_codes")
      .update({ verified: true })
      .eq("phone", phone)
      .eq("verified", false);

    if (invalidateError) {
      console.error(
        "[send-whatsapp-otp] Failed to invalidate old OTPs",
        invalidateError,
      );

      return json({ error: "internal_server_error" }, 500);
    }

    // ----------------------------------------------------------
    // Store new OTP
    // ----------------------------------------------------------

    const { error: insertError } = await admin
      .from("phone_otp_codes")
      .insert({
        phone,
        code_hash: codeHash,
        expires_at: expiresAt,
        attempts: 0,
        verified: false,
      });

    if (insertError) {
      console.error(
        "[send-whatsapp-otp] Failed to store OTP",
        insertError,
      );

      return json({ error: "internal_server_error" }, 500);
    }

    // ----------------------------------------------------------
    // Send OTP through Meta WhatsApp Cloud API
    // ----------------------------------------------------------

    const metaUrl =
      `https://graph.facebook.com/${metaApiVersion}/${metaPhoneNumberId}/messages`;

    const metaPayload = {
      messaging_product: "whatsapp",
      recipient_type: "individual",
      to: phone,
      type: "template",
      template: {
        name: metaTemplateName,
        language: {
          code: metaTemplateLanguage,
        },
        components: [
          {
            type: "body",
            parameters: [{ type: "text", text: otp }],
          },
          {
            type: "button",
            sub_type: "url",
            index: "0",
            parameters: [{ type: "text", text: otp }],
          },
        ],
      },
    };

    console.log("[send-whatsapp-otp] Sending WhatsApp OTP", {
      phone,
      template: metaTemplateName,
      language: metaTemplateLanguage,
      apiVersion: metaApiVersion,
    });

    const metaResponse = await fetch(metaUrl, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${metaAccessToken}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(metaPayload),
    });

    const metaData = await metaResponse.json();

    // ----------------------------------------------------------
    // Meta rejected message
    // ----------------------------------------------------------

    if (!metaResponse.ok) {
      console.error(
        "[send-whatsapp-otp] Meta rejected WhatsApp message",
        {
          status: metaResponse.status,
          error: metaData,
        },
      );

      // Delete OTP because Meta rejected the message
      await admin
        .from("phone_otp_codes")
        .delete()
        .eq("phone", phone)
        .eq("code_hash", codeHash);

      return json(
        {
          error: "otp_send_failed",
          meta_error: metaData?.error?.message ?? null,
          meta_code: metaData?.error?.code ?? null,
          meta_type: metaData?.error?.type ?? null,
        },
        400,
      );
    }

    // ----------------------------------------------------------
    // Success
    // ----------------------------------------------------------

    console.log("[send-whatsapp-otp] Meta accepted WhatsApp OTP", {
      phone,
      messageId: metaData?.messages?.[0]?.id ?? null,
    });

    return json({ success: true });
  } catch (error) {
    console.error("[send-whatsapp-otp] Unexpected error", error);

    return json({ error: "internal_server_error" }, 500);
  }
});
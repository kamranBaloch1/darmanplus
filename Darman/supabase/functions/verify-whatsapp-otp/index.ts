import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0";

const PLAY_TEST_OTP_BY_PHONE: Record<string, string> = {
  "+923000000000": "123456", // Doctor test account
  "+923000000001": "123456", // Patient test account
};

const OTP_EXPIRY_MINUTES = 5;
const MAX_OTP_ATTEMPTS = 5;

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

async function createSession(
  url: string,
  key: string,
  phone: string,
): Promise<Response> {
  const admin = createClient(url, key, {
    auth: {
      autoRefreshToken: false,
      persistSession: false,
    },
  });

  const email = `p${phone.slice(1)}@auth.internal`;

  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    phone,
    phone_confirm: true,
    user_metadata: {
      verified_phone: phone,
      auth_method: "whatsapp",
    },
  });

  let userId = created.data.user?.id ?? null;

  if (created.error) {
    // Returning user may already exist.
    // First try the indexed database lookup.
    const lookup = await admin.rpc("get_auth_user_id_by_phone", {
      p_phone: phone,
    });

    if (!lookup.error && typeof lookup.data === "string") {
      userId = lookup.data;
    }

    // Safe fallback if helper RPC is unavailable.
    if (!userId) {
      let page = 1;

      while (!userId) {
        const listed = await admin.auth.admin.listUsers({
          page,
          perPage: 1000,
        });

        if (listed.error) {
          console.error(
            "[verify-whatsapp-otp] Auth user lookup failed",
            { message: listed.error.message },
          );

          break;
        }

        const match = listed.data.users.find(
          (user) =>
            user.phone === phone ||
            user.email?.toLowerCase() === email.toLowerCase(),
        );

        userId = match?.id ?? null;

        if (userId || listed.data.users.length < 1000) {
          break;
        }

        page += 1;
      }
    }

    if (!userId) {
      console.error(
        "[verify-whatsapp-otp] Auth user could not be created or found",
        { message: created.error.message },
      );

      return json({ error: "user_creation_failed" }, 500);
    }

    const updated = await admin.auth.admin.updateUserById(userId, {
      email,
      email_confirm: true,
      phone,
      phone_confirm: true,
      user_metadata: {
        verified_phone: phone,
        auth_method: "whatsapp",
      },
    });

    if (updated.error) {
      console.error(
        "[verify-whatsapp-otp] Auth user update failed",
        { message: updated.error.message },
      );

      return json({ error: "session_creation_failed" }, 500);
    }
  }

  if (!userId) {
    return json({ error: "session_creation_failed" }, 500);
  }

  // Generate a Supabase magic-link token.
  const generated = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });

  const tokenHash = generated.data.properties?.hashed_token;

  if (generated.error || !tokenHash) {
    console.error(
      "[verify-whatsapp-otp] Session link creation failed",
      {
        message: generated.error?.message ?? "Missing token hash",
      },
    );

    return json({ error: "session_creation_failed" }, 500);
  }

  // Exchange the magic-link token for a Supabase session.
  const response = await fetch(`${url}/auth/v1/verify`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      type: "magiclink",
      token_hash: tokenHash,
    }),
  });

  const session = await response.json();

  if (
    !response.ok ||
    !session.access_token ||
    !session.refresh_token
  ) {
    console.error(
      "[verify-whatsapp-otp] Session token exchange failed",
      {
        status: response.status,
        code: session?.error_code ?? session?.error ?? null,
      },
    );

    return json({ error: "session_creation_failed" }, 500);
  }

  return json({
    refresh_token: session.refresh_token,
  });
}

serve(async (request) => {
  if (request.method !== "POST") {
    return json({ error: "method_not_allowed" }, 405);
  }

  let body: {
    phone?: unknown;
    otp?: unknown;
  };

  try {
    body = await request.json();
  } catch {
    return json({ error: "invalid_json" }, 400);
  }

  if (typeof body.phone !== "string") {
    return json({ error: "phone_required" }, 400);
  }

  if (typeof body.otp !== "string" || !/^\d{6}$/.test(body.otp)) {
    return json({ error: "otp_invalid" }, 400);
  }

  let phone: string;

  try {
    phone = normalizePhone(body.phone);
  } catch {
    return json({ error: "invalid_phone_format" }, 400);
  }

  const url = Deno.env.get("SUPABASE_URL")?.trim();
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim();

  if (!url || !key) {
    return json({ error: "server_misconfigured" }, 500);
  }

  try {
    const admin = createClient(url, key, {
      auth: {
        autoRefreshToken: false,
        persistSession: false,
      },
    });

    // ------------------------------------------------------------
    // Identify client IP
    // ------------------------------------------------------------

    const clientIp =
      request.headers.get("cf-connecting-ip") ??
        request.headers.get("x-real-ip") ??
        request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
        "unknown";

    // ------------------------------------------------------------
    // Verification rate limits
    //
    // Phone: 10 attempts / 10 minutes
    // IP:    30 attempts / 10 minutes
    // ------------------------------------------------------------

    const [phoneHash, ipHash] = await Promise.all([
      hash(`verify:phone:${phone}`),
      hash(`verify:ip:${clientIp}`),
    ]);

    const [phoneAllowed, ipAllowed] = await Promise.all([
      consumeLimit(admin, `verify_phone_${phoneHash}`, 10, 600),
      consumeLimit(admin, `verify_ip_${ipHash}`, 30, 600),
    ]);

    if (!phoneAllowed || !ipAllowed) {
      return json({ error: "max_attempts_reached" }, 429);
    }

    // ------------------------------------------------------------
    // Google Play test accounts
    //
    // These remain isolated from real WhatsApp delivery.
    // ------------------------------------------------------------

    const playTestOtp = PLAY_TEST_OTP_BY_PHONE[phone];

    if (playTestOtp) {
      if (body.otp !== playTestOtp) {
        return json({ error: "otp_invalid" }, 400);
      }

      return await createSession(url, key, phone);
    }

    // ------------------------------------------------------------
    // Find latest active OTP
    // ------------------------------------------------------------

    const { data: otpRecord, error: otpLookupError } = await admin
      .from("phone_otp_codes")
      .select("id, code_hash, expires_at, attempts, verified, created_at")
      .eq("phone", phone)
      .eq("verified", false)
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();

    if (otpLookupError) {
      console.error(
        "[verify-whatsapp-otp] OTP lookup failed",
        otpLookupError,
      );

      return json({ error: "internal_server_error" }, 500);
    }

    if (!otpRecord) {
      return json({ error: "otp_expired" }, 400);
    }

    // ------------------------------------------------------------
    // Check maximum OTP attempts
    // ------------------------------------------------------------

    if (otpRecord.attempts >= MAX_OTP_ATTEMPTS) {
      return json({ error: "max_attempts_reached" }, 429);
    }

    // ------------------------------------------------------------
    // Check expiration
    // ------------------------------------------------------------

    const expiresAt = new Date(otpRecord.expires_at).getTime();

    if (!Number.isFinite(expiresAt) || Date.now() >= expiresAt) {
      // Mark expired OTP as consumed.
      await admin
        .from("phone_otp_codes")
        .update({ verified: true })
        .eq("id", otpRecord.id)
        .eq("verified", false);

      return json({ error: "otp_expired" }, 400);
    }

    // ------------------------------------------------------------
    // Hash submitted OTP
    //
    // Plain OTP is never stored in the database.
    // ------------------------------------------------------------

    const submittedHash = await hash(`otp:${phone}:${body.otp}`);

    // ------------------------------------------------------------
    // Wrong OTP
    // ------------------------------------------------------------

    if (submittedHash !== otpRecord.code_hash) {
      const nextAttempts = otpRecord.attempts + 1;

      const updateResult = await admin
        .from("phone_otp_codes")
        .update({ attempts: nextAttempts })
        .eq("id", otpRecord.id)
        .eq("verified", false)
        .eq("attempts", otpRecord.attempts);

      if (updateResult.error) {
        console.error(
          "[verify-whatsapp-otp] Failed to increment OTP attempts",
          updateResult.error,
        );
      }

      if (nextAttempts >= MAX_OTP_ATTEMPTS) {
        return json({ error: "max_attempts_reached" }, 429);
      }

      return json({ error: "otp_invalid" }, 400);
    }

    // ------------------------------------------------------------
    // Correct OTP
    // ------------------------------------------------------------

    const verifiedUpdate = await admin
      .from("phone_otp_codes")
      .update({ verified: true })
      .eq("id", otpRecord.id)
      .eq("verified", false);

    if (verifiedUpdate.error) {
      console.error(
        "[verify-whatsapp-otp] Failed to mark OTP verified",
        verifiedUpdate.error,
      );

      return json({ error: "internal_server_error" }, 500);
    }

    // ------------------------------------------------------------
    // OTP verified.
    // Create/retrieve Supabase Auth user and session.
    // ------------------------------------------------------------

    return await createSession(url, key, phone);
  } catch (error) {
    console.error("[verify-whatsapp-otp] Unexpected error", error);

    return json({ error: "internal_server_error" }, 500);
  }
});
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0"

const PLAY_TEST_OTP_BY_PHONE: Record<string, string> = {
  "+923000000000": "123456", // Doctor test account
  "+923000000001": "123456", // Patient test account
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json" },
})

function normalizePhone(value: string): string {
  let phone = value.replace(/[\s()-]/g, "")
  if (phone.startsWith("03")) phone = `+92${phone.slice(1)}`
  else if (/^3\d{9}$/.test(phone)) phone = `+92${phone}`
  else if (phone.startsWith("92")) phone = `+${phone}`
  if (!/^\+923\d{9}$/.test(phone)) throw new Error("invalid_phone_format")
  return phone
}

async function hash(value: string): Promise<string> {
  const bytes = new TextEncoder().encode(value)
  const digest = await crypto.subtle.digest("SHA-256", bytes)
  return Array.from(new Uint8Array(digest))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
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
  })
  if (error) throw error
  return data === true
}

async function createSession(
  url: string,
  key: string,
  phone: string,
): Promise<Response> {
  const admin = createClient(url, key, { auth: { autoRefreshToken: false, persistSession: false } })
  const email = `p${phone.slice(1)}@auth.internal`

  const created = await admin.auth.admin.createUser({
    email,
    email_confirm: true,
    phone,
    phone_confirm: true,
    user_metadata: {
      verified_phone: phone,
      auth_method: "whatsapp",
    },
  })

  let userId = created.data.user?.id ?? null
  if (created.error) {
    // A returning user can already own either the generated email or phone.
    // Prefer the indexed database lookup. The paginated Auth lookup is a safe
    // fallback for deployments where that helper migration is not installed.
    const lookup = await admin.rpc("get_auth_user_id_by_phone", {
      p_phone: phone,
    })
    if (!lookup.error && typeof lookup.data === "string") {
      userId = lookup.data
    }

    if (!userId) {
      let page = 1
      while (!userId) {
        const listed = await admin.auth.admin.listUsers({ page, perPage: 1000 })
        if (listed.error) {
          console.error("[verify-whatsapp-otp] Auth user lookup failed", {
            message: listed.error.message,
          })
          break
        }
        const match = listed.data.users.find((user) =>
          user.phone === phone || user.email?.toLowerCase() === email.toLowerCase()
        )
        userId = match?.id ?? null
        if (userId || listed.data.users.length < 1000) break
        page += 1
      }
    }

    if (!userId) {
      console.error("[verify-whatsapp-otp] Auth user could not be created or found", {
        message: created.error.message,
      })
      return json({ error: "user_creation_failed" }, 500)
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
    })
    if (updated.error) {
      console.error("[verify-whatsapp-otp] Auth user update failed", {
        message: updated.error.message,
      })
      return json({ error: "session_creation_failed" }, 500)
    }
  }

  if (!userId) return json({ error: "session_creation_failed" }, 500)

  // Mint the app session through Supabase's admin-generated magic-link token.
  // This avoids a password grant, which can be disabled independently in the
  // project's Auth settings even though email authentication is enabled.
  const generated = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  })
  const tokenHash = generated.data.properties?.hashed_token
  if (generated.error || !tokenHash) {
    console.error("[verify-whatsapp-otp] Session link creation failed", {
      message: generated.error?.message ?? "Missing token hash",
    })
    return json({ error: "session_creation_failed" }, 500)
  }

  const response = await fetch(`${url}/auth/v1/verify`, {
    method: "POST",
    headers: {
      apikey: key,
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ type: "magiclink", token_hash: tokenHash }),
  })
  const session = await response.json()
  if (!response.ok || !session.access_token || !session.refresh_token) {
    console.error("[verify-whatsapp-otp] Session token exchange failed", {
      status: response.status,
      code: session?.error_code ?? session?.error ?? null,
    })
    return json({ error: "session_creation_failed" }, 500)
  }
  return json({ refresh_token: session.refresh_token })
}

serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405)
  let body: { phone?: unknown; otp?: unknown }
  try { body = await request.json() } catch { return json({ error: "invalid_json" }, 400) }
  if (typeof body.phone !== "string") return json({ error: "phone_required" }, 400)
  if (typeof body.otp !== "string" || !/^\d{6}$/.test(body.otp)) return json({ error: "otp_invalid" }, 400)

  let phone: string
  try { phone = normalizePhone(body.phone) } catch { return json({ error: "invalid_phone_format" }, 400) }

  const url = Deno.env.get("SUPABASE_URL")?.trim()
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")?.trim()
  if (!url || !key) return json({ error: "server_misconfigured" }, 500)

  try {
    const admin = createClient(url, key, {
      auth: { autoRefreshToken: false, persistSession: false },
    })
    const clientIp =
      request.headers.get("cf-connecting-ip") ??
      request.headers.get("x-real-ip") ??
      request.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ??
      "unknown"
    const [phoneHash, ipHash] = await Promise.all([
      hash(`verify:phone:${phone}`),
      hash(`verify:ip:${clientIp}`),
    ])
    const [phoneAllowed, ipAllowed] = await Promise.all([
      consumeLimit(admin, `verify_phone_${phoneHash}`, 10, 600),
      consumeLimit(admin, `verify_ip_${ipHash}`, 30, 600),
    ])
    if (!phoneAllowed || !ipAllowed) {
      return json({ error: "max_attempts_reached" }, 429)
    }

    const playTestOtp = PLAY_TEST_OTP_BY_PHONE[phone]
    if (playTestOtp) {
      if (body.otp !== playTestOtp) {
        return json({ error: "otp_invalid" }, 400)
      }
      return await createSession(url, key, phone)
    }

    const accountSid = Deno.env.get("TWILIO_ACCOUNT_SID")?.trim()
    const authToken = Deno.env.get("TWILIO_AUTH_TOKEN")?.trim()
    const serviceSid = Deno.env.get("TWILIO_VERIFY_SERVICE_SID")?.trim()
    if (!accountSid || !authToken || !serviceSid) {
      return json({ error: "server_misconfigured" }, 500)
    }

    const response = await fetch(`https://verify.twilio.com/v2/Services/${serviceSid}/VerificationCheck`, {
      method: "POST",
      headers: {
        Authorization: `Basic ${btoa(`${accountSid}:${authToken}`)}`,
        "Content-Type": "application/x-www-form-urlencoded",
      },
      body: new URLSearchParams({ To: phone, Code: body.otp }),
    })
    const result = await response.json()
    if (!response.ok) {
      if (result?.code === 60202) return json({ error: "max_attempts_reached" }, 429)
      if (result?.code === 60203 || result?.code === 20404) return json({ error: "otp_expired" }, 400)
      return json({ error: "otp_invalid" }, 400)
    }
    if (result.status !== "approved") return json({ error: "otp_invalid" }, 400)
    return await createSession(url, key, phone)
  } catch (error) {
    console.error("verify-whatsapp-otp", error)
    return json({ error: "twilio_error" }, 500)
  }
})

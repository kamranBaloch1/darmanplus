import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0"

const headers = { "Content-Type": "application/json" }
const PLAY_REVIEW_DOCTOR_ID = "9b9dd1ed-c6a2-459a-9035-a209f350c0b8"
const PLAY_REVIEW_PATIENT_ID = "364705c0-2319-468d-8871-d17bb2a33c25"
const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers })

serve(async (request) => {
  if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405)

  let body: { specialization?: unknown }
  try { body = await request.json() } catch { return json({ error: "invalid_json" }, 400) }

  const specialization = typeof body.specialization === "string"
    ? body.specialization.trim()
    : ""
  if (specialization.length > 100) {
    return json({ error: "invalid_specialization" }, 400)
  }

  const url = Deno.env.get("SUPABASE_URL")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!url || !serviceRoleKey) return json({ error: "server_misconfigured" }, 500)

  const admin = createClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  let requesterId = ""
  const authorization = request.headers.get("Authorization")
  const accessToken = authorization?.replace(/^Bearer\s+/i, "").trim()
  if (accessToken) {
    const { data: { user } } = await admin.auth.getUser(accessToken)
    requesterId = user?.id ?? ""
  }

  const { data: audienceRows, error: audienceError } = await admin
    .from("doctor_catalogue_audience")
    .select("doctor_id, patient_id")

  // Fail closed: a missing/broken access list must never make a restricted
  // doctor visible to the public catalogue.
  if (audienceError) {
    console.error("[public-doctors] audience query failed", audienceError.message)
    return json({ error: "doctor_catalogue_failed" }, 500)
  }

  const restrictedDoctorIds = new Set(
    (audienceRows ?? []).map((row) => String(row.doctor_id)),
  )
  const allowedRestrictedDoctorIds = new Set(
    (audienceRows ?? [])
      .filter((row) => String(row.patient_id) === requesterId)
      .map((row) => String(row.doctor_id)),
  )

  let query = admin
    .from("users")
    .select(`
      uid,
      name,
      role,
      profile_image,
      is_profile_completed,
      gender,
      title,
      specialization,
      qualification,
      experience_years,
      consultation_fee,
      bio,
      intro_video_url,
      is_doctor_verified,
      is_available,
      doctor_rating,
      doctor_review_count,
      doctor_completed_consultation_count
    `)
    .eq("role", "doctor")
    .eq("is_doctor_verified", true)
    .eq("is_profile_completed", true)
    // Keep unavailable doctors discoverable, but always place currently
    // available doctors first. Rating decides the order inside each group.
    .order("is_available", { ascending: false, nullsFirst: false })
    .order("doctor_rating", { ascending: false, nullsFirst: false })
    .order("doctor_review_count", { ascending: false, nullsFirst: false })
    .limit(100)

  if (requesterId === PLAY_REVIEW_PATIENT_ID) {
    query = query.eq("uid", PLAY_REVIEW_DOCTOR_ID)
  } else {
    query = query.neq("uid", PLAY_REVIEW_DOCTOR_ID)
  }
  if (specialization) query = query.eq("specialization", specialization)
  const { data, error } = await query

  if (error) {
    console.error("[public-doctors] query failed", error.message)
    return json({ error: "doctor_catalogue_failed" }, 500)
  }

  const visibleDoctors = (data ?? []).filter((doctor) => {
    const doctorId = String(doctor.uid)
    return !restrictedDoctorIds.has(doctorId) ||
      allowedRestrictedDoctorIds.has(doctorId)
  })

  return json({ doctors: visibleDoctors })
})

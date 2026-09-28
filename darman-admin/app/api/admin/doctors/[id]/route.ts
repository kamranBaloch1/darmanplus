import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import crypto from "crypto";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const adminEmails = new Set(
  (process.env.DARMAN_ADMIN_EMAILS ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean),
);

async function adminClient(request: NextRequest) {
  if (!url || !service) return null;
  const client = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user?.email || !adminEmails.has(data.user.email.toLowerCase())) {
    return null;
  }
  return client;
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const client = await adminClient(request);
  if (!client) {
    return NextResponse.json({ error: "You are not authorized to access Darman Admin." }, { status: 403 });
  }

  const { id } = await params;
  const { data: doctor, error: doctorError } = await client
    .from("users")
    .select("uid,name,email,is_email_verified,phone,is_phone_verified,role,profile_image,is_profile_completed,gender,date_of_birth,title,specialization,qualification,medical_license_number,experience_years,consultation_fee,bio,intro_video_url,doctor_documents,is_doctor_verified,is_available,doctor_rating,doctor_review_count,doctor_completed_consultation_count,wallet_balance,wallet_reserved_balance,wallet_recovery_due,created_at,updated_at")
    .eq("uid", id)
    .eq("role", "doctor")
    .single();

  if (doctorError) {
    return NextResponse.json({ error: doctorError.code === "PGRST116" ? "Doctor not found." : doctorError.message }, { status: doctorError.code === "PGRST116" ? 404 : 500 });
  }

  const [bookingsResult, ratingsResult, walletResult] = await Promise.all([
    client
      .from("bookings")
      .select("id,patient_id,status,consultation_fee,gross_fee,commission_amount,doctor_earning,admin_refunded_at,admin_refund_reason,created_at,accepted_at,started_at,completed_at,cancelled_at,cancellation_reason,follow_up_date,follow_up_ended_at")
      .eq("doctor_id", id)
      .order("created_at", { ascending: false })
      .limit(100),
    client
      .from("consultation_ratings")
      .select("id,booking_id,patient_id,rating,review,created_at")
      .eq("doctor_id", id)
      .order("created_at", { ascending: false })
      .limit(100),
    client
      .from("wallet_transactions")
      .select("id,booking_id,transaction_type,amount,balance_after,description,created_at")
      .eq("user_id", id)
      .order("created_at", { ascending: false })
      .limit(50),
  ]);

  if (bookingsResult.error || ratingsResult.error || walletResult.error) {
    return NextResponse.json({ error: bookingsResult.error?.message ?? ratingsResult.error?.message ?? walletResult.error?.message ?? "Could not load doctor details." }, { status: 500 });
  }

  const peopleIds = [...new Set([...(bookingsResult.data ?? []).map((booking) => booking.patient_id), ...(ratingsResult.data ?? []).map((rating) => rating.patient_id)])];
  const { data: people, error: peopleError } = peopleIds.length
    ? await client.from("users").select("uid,name,profile_image,phone").in("uid", peopleIds)
    : { data: [], error: null };
  if (peopleError) return NextResponse.json({ error: peopleError.message }, { status: 500 });

  const personById = new Map((people ?? []).map((person) => [person.uid, person]));
  const documents = (doctor.doctor_documents ?? []).map((path: string) => ({
    path,
    url: client.storage.from("doctor-documents").getPublicUrl(path).data.publicUrl,
  }));

  return NextResponse.json({
    doctor: { ...doctor, documents },
    bookings: (bookingsResult.data ?? []).map((booking) => ({ ...booking, patient: personById.get(booking.patient_id) ?? null })),
    ratings: (ratingsResult.data ?? []).map((rating) => ({ ...rating, patient: personById.get(rating.patient_id) ?? null })),
    transactions: walletResult.data ?? [],
  });
}

function b64url(value: string | Buffer) {
  return Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function notifyBeforeDeletion(client: any, userId: string) {
  try {
    const credentialsJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!credentialsJson) return;
    const credentials = JSON.parse(credentialsJson);
    const now = Math.floor(Date.now() / 1000);
    const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
    const claim = b64url(JSON.stringify({
      iss: credentials.client_email,
      scope: "https://www.googleapis.com/auth/firebase.messaging",
      aud: "https://oauth2.googleapis.com/token",
      iat: now,
      exp: now + 3600,
    }));
    const input = `${header}.${claim}`;
    const signature = crypto.createSign("RSA-SHA256").update(input).sign(credentials.private_key);
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: `${input}.${b64url(signature)}`,
      }),
    });
    const { access_token: accessToken } = await tokenResponse.json();
    if (!accessToken) return;

    const { data: devices } = await client.from("push_notification_tokens").select("token").eq("user_id", userId);
    if (!devices?.length) return;
    const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
    await Promise.all(devices.map(({ token }: { token: string }) => fetch(endpoint, {
      method: "POST",
      headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        message: {
          token,
          notification: {
            title: "Doctor registration removed",
            body: "Your doctor registration was removed because it could not be verified.",
          },
          data: { type: "doctor_account_deleted" },
          android: { priority: "HIGH", notification: { channel_id: "consultation_requests", sound: "default" } },
          apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", badge: 1 } } },
        },
      }),
    })));
  } catch (error) {
    console.error("Doctor deletion notification failed", error);
  }
}

export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const client = await adminClient(request);
  if (!client) {
    return NextResponse.json({ error: "You are not authorized to delete accounts." }, { status: 403 });
  }

  const { id } = await params;
  const { data: doctor, error: doctorError } = await client
    .from("users")
    .select("uid,role,is_doctor_verified,wallet_balance,wallet_reserved_balance,wallet_recovery_due,doctor_documents")
    .eq("uid", id)
    .eq("role", "doctor")
    .maybeSingle();
  if (doctorError || !doctor) {
    return NextResponse.json({ error: "Doctor account was not found." }, { status: 404 });
  }
  if (doctor.is_doctor_verified) {
    return NextResponse.json({ error: "Unverify this doctor before deleting the account." }, { status: 409 });
  }

  const { data: booking, error: bookingError } = await client
    .from("bookings")
    .select("id")
    .eq("doctor_id", id)
    .limit(1)
    .maybeSingle();
  if (bookingError) {
    return NextResponse.json({ error: bookingError.message }, { status: 500 });
  }
  if (booking) {
    return NextResponse.json({ error: "This doctor has consultation history and cannot be permanently deleted." }, { status: 409 });
  }

  const hasFunds = [doctor.wallet_balance, doctor.wallet_reserved_balance, doctor.wallet_recovery_due]
    .some((value) => Math.abs(Number(value ?? 0)) > 0.001);
  if (hasFunds) {
    return NextResponse.json({ error: "Clear this doctor's wallet balance before deleting the account." }, { status: 409 });
  }

  await notifyBeforeDeletion(client, id);

  const { error: deleteError } = await client.auth.admin.deleteUser(id);
  if (deleteError) {
    return NextResponse.json({ error: deleteError.message }, { status: 500 });
  }

  const documents = Array.isArray(doctor.doctor_documents)
    ? doctor.doctor_documents.filter((path): path is string => typeof path === "string" && path.length > 0)
    : [];
  if (documents.length) {
    await client.storage.from("doctor-documents").remove(documents);
  }

  return NextResponse.json({ ok: true });
}

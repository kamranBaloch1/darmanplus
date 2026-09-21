import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import crypto from "crypto";
const url = process.env.NEXT_PUBLIC_SUPABASE_URL,
  service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const emails = new Set(
  (process.env.DARMAN_ADMIN_EMAILS ?? "")
    .split(",")
    .map((x) => x.trim().toLowerCase())
    .filter(Boolean),
);
function b64url(value: string | Buffer) {
  return Buffer.from(value)
    .toString("base64")
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}
async function notifyVerified(client: any, userId: string) {
  try {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!raw) return;
    const credentials = JSON.parse(raw),
      now = Math.floor(Date.now() / 1000),
      header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" })),
      claim = b64url(
        JSON.stringify({
          iss: credentials.client_email,
          scope: "https://www.googleapis.com/auth/firebase.messaging",
          aud: "https://oauth2.googleapis.com/token",
          iat: now,
          exp: now + 3600,
        }),
      ),
      input = `${header}.${claim}`,
      signature = crypto
        .createSign("RSA-SHA256")
        .update(input)
        .sign(credentials.private_key);
    const authResponse = await fetch("https://oauth2.googleapis.com/token", {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
        assertion: `${input}.${b64url(signature)}`,
      }),
    });
    const { access_token } = await authResponse.json();
    if (!access_token) return;
    const { data: devices } = await client
      .from("push_notification_tokens")
      .select("token")
      .eq("user_id", userId);
    if (!devices?.length) return;
    const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
    await Promise.all(
      devices.map(({ token }: { token: string }) =>
        fetch(endpoint, {
          method: "POST",
          headers: {
            Authorization: `Bearer ${access_token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title: "Your doctor profile is verified",
                body: "Congratulations! Your doctor profile has been approved. You can now go online and start receiving consultation requests.",
              },
              data: { type: "doctor_verified" },
              android: {
                priority: "HIGH",
                notification: {
                  channel_id: "consultation_requests",
                  sound: "default",
                },
              },
              apns: {
                headers: { "apns-priority": "10" },
                payload: { aps: { sound: "default", badge: 1 } },
              },
            },
          }),
        }),
      ),
    );
  } catch (error) {
    console.error("Doctor verification notification failed", error);
  }
}
export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  if (!url || !service)
    return NextResponse.json(
      { error: "Admin server is not configured." },
      { status: 500 },
    );
  const client = createClient(url, service, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
    token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await client.auth.getUser(token);
  if (
    authError ||
    !auth.user?.email ||
    !emails.has(auth.user.email.toLowerCase())
  )
    return NextResponse.json(
      { error: "You are not authorized to verify doctors." },
      { status: 403 },
    );
  const { id } = await params;
  const { data: doctor } = await client
    .from("users")
    .select("uid,role,doctor_documents")
    .eq("uid", id)
    .maybeSingle();
  if (!doctor || doctor.role !== "doctor")
    return NextResponse.json(
      { error: "Doctor profile was not found." },
      { status: 404 },
    );
  if (
    !Array.isArray(doctor.doctor_documents) ||
    doctor.doctor_documents.length === 0
  )
    return NextResponse.json(
      { error: "This doctor has not uploaded verification documents." },
      { status: 422 },
    );
  const { error } = await client
    .from("users")
    .update({ is_doctor_verified: true, updated_at: new Date().toISOString() })
    .eq("uid", id);
  if (error)
    return NextResponse.json({ error: error.message }, { status: 500 });
  await notifyVerified(client, id);
  return NextResponse.json({ ok: true });
}
export async function DELETE(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  if (!url || !service)
    return NextResponse.json(
      { error: "Admin server is not configured." },
      { status: 500 },
    );
  const client = createClient(url, service, {
      auth: { persistSession: false, autoRefreshToken: false },
    }),
    token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await client.auth.getUser(token);
  if (
    authError ||
    !auth.user?.email ||
    !emails.has(auth.user.email.toLowerCase())
  )
    return NextResponse.json(
      { error: "You are not authorized to update doctors." },
      { status: 403 },
    );
  const { id } = await params;
  const { data: doctor } = await client
    .from("users")
    .select("uid,role")
    .eq("uid", id)
    .maybeSingle();
  if (!doctor || doctor.role !== "doctor")
    return NextResponse.json(
      { error: "Doctor profile was not found." },
      { status: 404 },
    );
  const { error } = await client
    .from("users")
    .update({
      is_doctor_verified: false,
      is_available: false,
      updated_at: new Date().toISOString(),
    })
    .eq("uid", id);
  return error
    ? NextResponse.json({ error: error.message }, { status: 500 })
    : NextResponse.json({ ok: true });
}

import crypto from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const adminEmails = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map((value) => value.trim().toLowerCase()).filter(Boolean));
function b64url(value: string | Buffer) { return Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", ""); }

async function notify(client: any, userId: string, title: string, body: string, bookingId: string) {
  try {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!raw) return;
    const credentials = JSON.parse(raw), now = Math.floor(Date.now() / 1000);
    const input = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify({ iss: credentials.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }))}`;
    const signature = crypto.createSign("RSA-SHA256").update(input).sign(credentials.private_key);
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${input}.${b64url(signature)}` }) });
    const { access_token: accessToken } = await tokenResponse.json();
    if (!accessToken) return;
    const { data: devices } = await client.from("push_notification_tokens").select("token").eq("user_id", userId);
    if (!devices?.length) return;
    const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
    await Promise.all(devices.map(({ token }: { token: string }) => fetch(endpoint, { method: "POST", headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: JSON.stringify({ message: { token, notification: { title, body }, data: { type: "consultation_cancelled", booking_id: bookingId }, android: { priority: "HIGH", notification: { channel_id: "consultation_requests", sound: "default" } }, apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", badge: 1 } } } } }) })));
  } catch (error) { console.error("Admin consultation cancellation notification failed", error); }
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!url || !service) return NextResponse.json({ error: "Admin server is not configured." }, { status: 500 });
  const client = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth, error: authError } = await client.auth.getUser(token), email = auth.user?.email?.toLowerCase();
  if (authError || !email || !adminEmails.has(email)) return NextResponse.json({ error: "You are not authorized to cancel consultations." }, { status: 403 });
  const { id } = await params, body = await request.json().catch(() => ({})), reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (reason.length < 5 || reason.length > 500) return NextResponse.json({ error: "Enter a clear cancellation reason between 5 and 500 characters." }, { status: 422 });
  const { data, error } = await client.rpc("admin_cancel_active_consultation", { p_booking_id: id, p_reason: reason, p_admin_email: email });
  if (error) {
    const message = error.message.includes("Only active") ? "Only an ongoing consultation can be cancelled." : error.message.includes("reserved funds") ? "The patient’s reserved wallet amount is incomplete, so cancellation was stopped." : "The consultation could not be cancelled. Please review it and try again.";
    return NextResponse.json({ error: message }, { status: 409 });
  }
  const result = data as { patient_id: string; doctor_id: string; patient_refund: number };
  const amount = `Rs. ${Number(result.patient_refund).toLocaleString("en-PK")}`;
  await Promise.all([
    notify(client, result.patient_id, "Consultation cancelled", `Darman support cancelled this consultation. ${amount} has been returned to your wallet. Reason: ${reason}`, id),
    notify(client, result.doctor_id, "Consultation cancelled by Darman", `Darman support cancelled this consultation. Reason: ${reason}`, id),
  ]);
  return NextResponse.json({ ok: true, cancellation: result });
}

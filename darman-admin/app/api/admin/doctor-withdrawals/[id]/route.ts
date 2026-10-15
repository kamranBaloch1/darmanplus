import crypto from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(x => x.trim().toLowerCase()).filter(Boolean));
const b64url = (value: string | Buffer) => Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");

async function notifyDoctor(client: any, doctorId: string, title: string, body: string, requestId: string) {
  try {
    const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!raw) return;
    const credentials = JSON.parse(raw), now = Math.floor(Date.now() / 1000);
    const assertionBody = `${b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }))}.${b64url(JSON.stringify({ iss: credentials.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }))}`;
    const signature = crypto.createSign("RSA-SHA256").update(assertionBody).sign(credentials.private_key);
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${assertionBody}.${b64url(signature)}` }) });
    const { access_token: accessToken } = await tokenResponse.json();
    if (!accessToken) return;
    const { data: devices } = await client.from("push_notification_tokens").select("token").eq("user_id", doctorId);
    if (!devices?.length) return;
    const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
    await Promise.all(devices.map(({ token }: { token: string }) => fetch(endpoint, { method: "POST", headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: JSON.stringify({ message: { token, notification: { title, body }, data: { type: "doctor_withdrawal_update", withdrawal_request_id: requestId }, android: { priority: "HIGH", notification: { channel_id: "consultation_requests", sound: "default" } }, apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", badge: 1 } } } } }) })));
  } catch (error) { console.error("Doctor withdrawal notification failed", error); }
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  if (!url || !service) return NextResponse.json({ error: "Admin server is not configured." }, { status: 500 });
  const client = createClient(url, service, { auth: { persistSession: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth } = await client.auth.getUser(token), email = auth.user?.email?.toLowerCase();
  if (!email || !admins.has(email)) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  const { id } = await params;
  const body = await request.json().catch(() => ({}));
  const action = body.action === "approve" ? "approve" : body.action === "reject" ? "reject" : "";
  const reason = typeof body.reason === "string" ? body.reason.trim() : "";
  if (!action) return NextResponse.json({ error: "Choose approve or reject." }, { status: 422 });
  if (action === "reject" && reason.length < 5) return NextResponse.json({ error: "Enter a clear rejection reason." }, { status: 422 });
  const { data, error } = await client.rpc("admin_process_doctor_withdrawal_request", { p_request_id: id, p_action: action, p_reason: reason, p_admin_email: email });
  if (error) return NextResponse.json({ error: error.message }, { status: 409 });
  const result = data as { doctor_id: string; amount: number; bank_name: string; status: "approved" | "rejected" };
  const amount = `Rs. ${Number(result.amount).toLocaleString("en-PK")}`;
  await notifyDoctor(
    client,
    result.doctor_id,
    result.status === "approved" ? "Withdrawal sent" : "Withdrawal request rejected",
    result.status === "approved"
      ? `${amount} has been sent to your ${result.bank_name} account.`
      : `${amount} was returned to your wallet. Reason: ${reason}`,
    id,
  );
  return NextResponse.json({ ok: true, result: data });
}

import crypto from "crypto";
import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean));
const b64url = (value: string | Buffer) => Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");

async function authorize(request: NextRequest) {
  if (!url || !service) return { client: null, email: null };
  const client = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data } = await client.auth.getUser(token);
  const email = data.user?.email?.toLowerCase() ?? null;
  return { client: email && admins.has(email) ? client : null, email };
}

export async function GET(request: NextRequest) {
  const { client } = await authorize(request);
  if (!client) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  const role = request.nextUrl.searchParams.get("role");
  const q = (request.nextUrl.searchParams.get("q") ?? "").trim().replace(/[,%()]/g, " ");
  if (role !== "doctor" && role !== "patient") return NextResponse.json({ users: [] });
  let query = client.from("users").select("uid,name,phone,email,profile_image,role").eq("role", role).order("name").limit(20);
  if (q) query = query.or(`name.ilike.%${q}%,phone.ilike.%${q}%,email.ilike.%${q}%`);
  const { data, error } = await query;
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  return NextResponse.json({ users: data ?? [] });
}

export async function POST(request: NextRequest) {
  const { client, email } = await authorize(request);
  if (!client || !email) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  const body = await request.json().catch(() => ({}));
  const audience = String(body.audience ?? ""), title = String(body.title ?? "").trim(), message = String(body.message ?? "").trim(), recipientId = typeof body.recipient_id === "string" ? body.recipient_id : null;
  if (!["all_doctors", "all_patients", "specific_doctor", "specific_patient"].includes(audience)) return NextResponse.json({ error: "Choose an announcement audience." }, { status: 422 });
  if (title.length < 3 || title.length > 80 || message.length < 3 || message.length > 500) return NextResponse.json({ error: "Use a title of 3–80 characters and a message of 3–500 characters." }, { status: 422 });
  const isSpecific = audience.startsWith("specific_");
  if (isSpecific && !recipientId) return NextResponse.json({ error: "Choose a recipient." }, { status: 422 });
  const role = audience.endsWith("doctors") || audience.endsWith("doctor") ? "doctor" : "patient";
  let userQuery = client.from("users").select("uid").eq("role", role);
  if (recipientId) userQuery = userQuery.eq("uid", recipientId);
  const { data: recipients, error: recipientError } = await userQuery;
  if (recipientError || !recipients?.length) return NextResponse.json({ error: "No matching recipients were found." }, { status: 422 });
  const ids = recipients.map(item => item.uid);
  const { data: tokens } = await client.from("push_notification_tokens").select("token,user_id").in("user_id", ids);
  const raw = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
  let delivered = 0;
  if (raw && tokens?.length) {
    const credentials = JSON.parse(raw), now = Math.floor(Date.now() / 1000);
    const header = b64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
    const payload = b64url(JSON.stringify({ iss: credentials.client_email, scope: "https://www.googleapis.com/auth/firebase.messaging", aud: "https://oauth2.googleapis.com/token", iat: now, exp: now + 3600 }));
    const input = `${header}.${payload}`;
    const signature = crypto.createSign("RSA-SHA256").update(input).sign(credentials.private_key);
    const tokenResponse = await fetch("https://oauth2.googleapis.com/token", { method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" }, body: new URLSearchParams({ grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer", assertion: `${input}.${b64url(signature)}` }) });
    const { access_token: accessToken } = await tokenResponse.json();
    if (accessToken) {
      const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
      const results = await Promise.all(tokens.map(({ token }) => fetch(endpoint, { method: "POST", headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" }, body: JSON.stringify({ message: { token, notification: { title, body: message }, data: { type: "admin_announcement", audience }, android: { priority: "HIGH", notification: { channel_id: "consultation_requests", sound: "default" } }, apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", badge: 1 } } } } }) })));
      delivered = results.filter(result => result.ok).length;
    }
  }
  await client.from("admin_announcements").insert({ sent_by: email, audience, recipient_id: recipientId, title, message, recipient_count: ids.length, delivered_count: delivered });
  return NextResponse.json({ ok: true, recipients: ids.length, delivered });
}

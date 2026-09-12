import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";
import crypto from "crypto";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(x => x.trim().toLowerCase()).filter(Boolean));

async function admin(request: NextRequest) {
  if (!url || !service) return null;
  const client = createClient(url, service, { auth: { persistSession: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data } = await client.auth.getUser(token);
  return data.user?.email && admins.has(data.user.email.toLowerCase()) ? { client, email: data.user.email } : null;
}

function b64url(value: string | Buffer) {
  return Buffer.from(value).toString("base64").replaceAll("+", "-").replaceAll("/", "_").replaceAll("=", "");
}

async function firebaseAccessToken(credentials: any) {
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
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: `${input}.${b64url(signature)}`,
    }),
  });
  const data = await response.json();
  return data.access_token as string | undefined;
}

async function notifyPatient(client: any, userId: string, payload: { title: string; body: string; type: string; topUpId: string; amount?: number; reason?: string }) {
  try {
    const credentialsJson = process.env.FIREBASE_SERVICE_ACCOUNT_JSON;
    if (!credentialsJson) return;
    const credentials = JSON.parse(credentialsJson);
    const accessToken = await firebaseAccessToken(credentials);
    if (!accessToken) return;

    const { data: devices } = await client.from("push_notification_tokens").select("token").eq("user_id", userId);
    if (!devices?.length) return;

    const endpoint = `https://fcm.googleapis.com/v1/projects/${credentials.project_id}/messages:send`;
    await Promise.all(devices.map(async ({ token }: { token: string }) => {
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" },
        body: JSON.stringify({
          message: {
            token,
            notification: { title: payload.title, body: payload.body },
            data: {
              type: payload.type,
              top_up_request_id: payload.topUpId,
              amount: payload.amount == null ? "" : String(payload.amount),
              reason: payload.reason ?? "",
            },
            android: { priority: "HIGH", ttl: "3600s", notification: { channel_id: "consultation_requests", sound: "default", visibility: "PRIVATE" } },
            apns: { headers: { "apns-priority": "10" }, payload: { aps: { sound: "default", badge: 1 } } },
          },
        }),
      });
      if (!response.ok && (await response.text()).includes("UNREGISTERED")) {
        await client.from("push_notification_tokens").delete().eq("token", token);
      }
    }));
  } catch (error) {
    console.error("Manual top-up notification failed", error);
  }
}

async function createWalletTopUpTransaction(client: any, topUp: any, amount: number, newBalance: number, email: string) {
  const base = {
    user_id: topUp.user_id,
    booking_id: null,
    transaction_type: "wallet_top_up",
    amount,
    balance_after: newBalance,
    reserved_balance_after: null,
    description: "JazzCash wallet top-up approved by admin",
    metadata: { provider: "jazzcash", receipt_url: topUp.receipt_url, manual_admin_email: email },
  };
  const withTopUpId = { ...base, top_up_request_id: topUp.id };
  let result = await client.from("wallet_transactions").insert(withTopUpId).select("id").single();
  if (!result.error) return result;
  if (String(result.error.message ?? "").includes("top_up_request_id")) {
    result = await client.from("wallet_transactions").insert(base).select("id").single();
  }
  return result;
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const access = await admin(request);
  if (!access) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });

  const { id } = await params;
  const body = await request.json();
  const action = String(body.action ?? "");
  const amount = Number(body.amount);
  const reason = String(body.reason ?? "").trim();
  const { client, email } = access;

  const { data: topUp, error: loadError } = await client
    .from("wallet_top_up_requests")
    .select("*")
    .eq("id", id)
    .single();
  if (loadError || !topUp) return NextResponse.json({ error: loadError?.message ?? "Top-up request not found" }, { status: 404 });
  if (!["pending", "submitted"].includes(topUp.status)) return NextResponse.json({ error: "This request is already processed." }, { status: 409 });

  if (action === "reject") {
    const { error } = await client.from("wallet_top_up_requests").update({
      status: "failed",
      response_message: reason || "Manual payment rejected by admin",
      response_payload: { ...(topUp.response_payload ?? {}), manual_admin_email: email, rejection_reason: reason || null },
      completed_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }).eq("id", id);
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    await notifyPatient(client, topUp.user_id, {
      title: "Wallet top-up rejected",
      body: reason ? `Your payment receipt was rejected: ${reason}` : "Your  payment was rejected. Please upload a valid receipt.",
      type: "wallet_top_up_rejected",
      topUpId: id,
      reason,
    });
    return NextResponse.json({ ok: true });
  }

  if (action !== "approve" || !Number.isFinite(amount) || amount <= 0) {
    return NextResponse.json({ error: "Enter a valid approved amount." }, { status: 400 });
  }

  const { data: user, error: userError } = await client
    .from("users")
    .select("uid,wallet_balance")
    .eq("uid", topUp.user_id)
    .single();
  if (userError || !user) return NextResponse.json({ error: userError?.message ?? "User not found" }, { status: 404 });

  const newBalance = Number(user.wallet_balance ?? 0) + amount;
  const now = new Date().toISOString();
  const { error: balanceError } = await client.from("users").update({ wallet_balance: newBalance, updated_at: now }).eq("uid", topUp.user_id);
  if (balanceError) return NextResponse.json({ error: balanceError.message }, { status: 500 });

  const { data: tx, error: txError } = await createWalletTopUpTransaction(client, topUp, amount, newBalance, email);
  if (txError) return NextResponse.json({ error: txError.message }, { status: 500 });

  const { error: updateError } = await client.from("wallet_top_up_requests").update({
    amount,
    amount_minor: Math.round(amount * 100),
    status: "succeeded",
    response_code: "MANUAL_APPROVED",
    response_message: "Manual payment approved by admin",
    response_payload: { ...(topUp.response_payload ?? {}), manual_admin_email: email },
    wallet_transaction_id: tx.id,
    completed_at: now,
    updated_at: now,
  }).eq("id", id);

  if (updateError) return NextResponse.json({ error: updateError.message }, { status: 500 });
  await notifyPatient(client, topUp.user_id, {
    title: "Wallet credited",
    body: `Rs. ${amount.toLocaleString("en-PK")} has been credited to your wallet.`,
    type: "wallet_top_up_approved",
    topUpId: id,
    amount,
  });
  return NextResponse.json({ ok: true });
}

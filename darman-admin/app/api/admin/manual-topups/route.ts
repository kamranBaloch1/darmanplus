import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(x => x.trim().toLowerCase()).filter(Boolean));

async function admin(request: NextRequest) {
  if (!url || !service) return null;
  const client = createClient(url, service, { auth: { persistSession: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data } = await client.auth.getUser(token);
  return data.user?.email && admins.has(data.user.email.toLowerCase()) ? client : null;
}

export async function GET(request: NextRequest) {
  const client = await admin(request);
  if (!client) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });

  const { data: requests, error } = await client
    .from("wallet_top_up_requests")
    .select("id,user_id,amount,currency,payment_method,provider,receipt_url,status,response_message,provider_reference,wallet_transaction_id,created_at,submitted_at,completed_at,updated_at")
    .not("receipt_url", "is", null)
    .order("created_at", { ascending: false })
    .limit(100);

  if (error) return NextResponse.json({ error: error.message }, { status: 500 });

  const userIds = [...new Set((requests ?? []).map(x => x.user_id).filter(Boolean))];
  const { data: users } = userIds.length
    ? await client.from("users").select("uid,name,email,phone,profile_image,wallet_balance").in("uid", userIds)
    : { data: [] };
  const byId = new Map((users ?? []).map(x => [x.uid, x]));

  const rows = await Promise.all((requests ?? []).map(async x => {
    let receipt_signed_url = x.receipt_url;
    if (x.receipt_url && !/^https?:\/\//i.test(x.receipt_url)) {
      const signed = await client.storage.from("wallet-receipts").createSignedUrl(x.receipt_url, 60 * 10);
      receipt_signed_url = signed.data?.signedUrl ?? x.receipt_url;
    }
    return { ...x, receipt_signed_url, user: byId.get(x.user_id) ?? null };
  }));

  return NextResponse.json({ requests: rows });
}

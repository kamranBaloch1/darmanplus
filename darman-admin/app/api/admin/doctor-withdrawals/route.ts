import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(x => x.trim().toLowerCase()).filter(Boolean));

export async function GET(request: NextRequest) {
  if (!url || !service) return NextResponse.json({ error: "Admin server is not configured." }, { status: 500 });
  const client = createClient(url, service, { auth: { persistSession: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth } = await client.auth.getUser(token);
  if (!auth.user?.email || !admins.has(auth.user.email.toLowerCase())) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });

  const { data: requests, error } = await client
    .from("doctor_withdrawal_requests")
    .select("*")
    .order("created_at", { ascending: false })
    .limit(200);
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  const ids = [...new Set((requests ?? []).map(x => x.doctor_id))];
  const { data: doctors } = ids.length ? await client.from("users").select("uid,name,phone,email,profile_image,wallet_balance").in("uid", ids) : { data: [] };
  const byId = new Map((doctors ?? []).map(x => [x.uid, x]));
  return NextResponse.json({ requests: (requests ?? []).map(x => ({ ...x, doctor: byId.get(x.doctor_id) ?? null })) });
}

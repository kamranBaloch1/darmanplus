import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean));

async function authorize(request: NextRequest) {
  if (!url || !service) return null;
  const client = createClient(url, service, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data } = await client.auth.getUser(token);
  return data.user?.email && admins.has(data.user.email.toLowerCase()) ? client : null;
}

export async function GET(request: NextRequest) {
  const client = await authorize(request);
  if (!client) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });

  const { data: setting, error } = await client.from("manual_payment_settings")
    .select("storage_path,updated_at").eq("setting_key", "jazzcash_qr").maybeSingle();
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  if (!setting) return NextResponse.json({ qr_url: null, updated_at: null });

  const { data: signed, error: signError } = await client.storage
    .from("manual-payment-qr").createSignedUrl(setting.storage_path, 60 * 10);
  if (signError) return NextResponse.json({ error: signError.message }, { status: 500 });
  return NextResponse.json({ qr_url: signed.signedUrl, updated_at: setting.updated_at });
}

export async function POST(request: NextRequest) {
  const client = await authorize(request);
  if (!client) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });

  const form = await request.formData().catch(() => null);
  const file = form?.get("file");
  if (!(file instanceof File)) return NextResponse.json({ error: "Choose a QR image to upload." }, { status: 422 });
  const allowed = new Set(["image/jpeg", "image/png", "image/webp"]);
  if (!allowed.has(file.type)) return NextResponse.json({ error: "Upload a JPG, PNG, or WebP image." }, { status: 422 });
  if (!file.size || file.size > 5 * 1024 * 1024) return NextResponse.json({ error: "Image must be 5 MB or smaller." }, { status: 422 });

  const extension = file.type === "image/png" ? "png" : file.type === "image/webp" ? "webp" : "jpg";
  const path = `jazzcash/payment-qr-${Date.now()}.${extension}`;
  const { error: uploadError } = await client.storage.from("manual-payment-qr").upload(path, await file.arrayBuffer(), {
    contentType: file.type, upsert: false, cacheControl: "3600",
  });
  if (uploadError) return NextResponse.json({ error: uploadError.message }, { status: 500 });

  const { data: previous } = await client.from("manual_payment_settings")
    .select("storage_path").eq("setting_key", "jazzcash_qr").maybeSingle();
  const { error: updateError } = await client.from("manual_payment_settings").upsert({
    setting_key: "jazzcash_qr", storage_path: path, updated_at: new Date().toISOString(),
  });
  if (updateError) {
    await client.storage.from("manual-payment-qr").remove([path]);
    return NextResponse.json({ error: updateError.message }, { status: 500 });
  }
  if (previous?.storage_path && previous.storage_path !== path) {
    await client.storage.from("manual-payment-qr").remove([previous.storage_path]);
  }

  const { data: signed, error: signError } = await client.storage
    .from("manual-payment-qr").createSignedUrl(path, 60 * 10);
  if (signError) return NextResponse.json({ error: signError.message }, { status: 500 });
  return NextResponse.json({ qr_url: signed.signedUrl, updated_at: new Date().toISOString() });
}

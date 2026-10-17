import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") return json({ error: "Method Not Allowed" }, 405);

  const authorization = req.headers.get("Authorization");
  const url = Deno.env.get("SUPABASE_URL");
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization || !url || !serviceKey) {
    return json({ error: "Authentication required" }, 401);
  }

  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
  const accessToken = authorization.replace(/^Bearer\s+/i, "").trim();
  const { data: { user }, error: authError } = await admin.auth.getUser(accessToken);
  if (authError || !user) return json({ error: "Unauthorized" }, 401);

  const { data: setting, error } = await admin
    .from("manual_payment_settings")
    .select("storage_path")
    .eq("setting_key", "jazzcash_qr")
    .maybeSingle();
  if (error) {
    console.error("[manual-payment-qr] settings query failed", error.message);
    return json({ error: "Payment QR is temporarily unavailable" }, 500);
  }
  if (!setting?.storage_path) return json({ error: "Payment QR has not been configured yet" }, 404);

  const { data: signed, error: signError } = await admin.storage
    .from("manual-payment-qr")
    .createSignedUrl(setting.storage_path, 60 * 60);
  if (signError || !signed?.signedUrl) {
    console.error("[manual-payment-qr] signed URL creation failed", signError?.message);
    return json({ error: "Payment QR is temporarily unavailable" }, 500);
  }

  return json({ qr_url: signed.signedUrl }, 200);
});

function json(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

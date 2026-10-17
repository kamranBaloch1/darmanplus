import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { sendDiscordWebhook } from "../_shared/discord.ts";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "Method Not Allowed" }, 405);
  }

  const authHeader = req.headers.get("Authorization");
  if (!authHeader) return json({ error: "Missing authorization" }, 401);

  const url = Deno.env.get("SUPABASE_URL")!;
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")!;
  const caller = createClient(url, anonKey, {
    global: { headers: { Authorization: authHeader } },
  });

  const { data: { user }, error: userError } = await caller.auth.getUser();
  if (userError || !user) return json({ error: "Unauthorized" }, 401);

  try {
    const body = await req.json();
    const amount = Number(body.amount);
    const bankName = String(body.bank_name ?? "").trim();
    const accountNumber = String(body.account_number ?? "").trim();
    const accountName = String(body.account_name ?? "").trim();

    const { data: request, error } = await caller.rpc(
      "create_doctor_withdrawal_request",
      {
        p_amount: amount,
        p_bank_name: bankName,
        p_account_number: accountNumber,
        p_account_name: accountName,
      },
    );
    if (error) return json({ error: error.message }, 400);
    if (!request) return json({ error: "Withdrawal request was not created" }, 500);

    let discordAlert: { sent: boolean; reason?: string } = {
      sent: false,
      reason: "Discord alert was not attempted",
    };
    try {
      const admin = createClient(
        url,
        Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
      );
      const { data: doctor } = await admin
        .from("users")
        .select("name, phone, email")
        .eq("uid", user.id)
        .maybeSingle();

      discordAlert = await sendDiscordWebhook({
        content: "New doctor withdrawal request",
        embeds: [{
          title: "Doctor withdrawal request",
          description: "A doctor requested a wallet withdrawal. Review it in Darman Admin.",
          color: 3447003,
          fields: [
            { name: "Doctor", value: doctor?.name?.toString().trim() || "Unknown doctor", inline: true },
            { name: "Phone", value: doctor?.phone?.toString().trim() || "No phone", inline: true },
            { name: "Email", value: doctor?.email?.toString().trim() || "-", inline: true },
            { name: "Amount", value: `${request.currency || "PKR"} ${request.amount}`, inline: true },
            { name: "Bank or wallet", value: bankName, inline: true },
            { name: "Account holder", value: accountName, inline: true },
            { name: "Account number", value: accountNumber, inline: false },
            { name: "Request ID", value: request.id?.toString() || "new request", inline: false },
          ],
          timestamp: new Date().toISOString(),
        }],
      });
    } catch (error) {
      console.error("DOCTOR WITHDRAWAL DISCORD ERROR:", error);
      discordAlert = { sent: false, reason: "Discord notification failed" };
    }

    return json({ request, discord_alert: discordAlert }, 200);
  } catch (error) {
    console.error("DOCTOR WITHDRAWAL REQUEST ERROR:", error);
    return json({
      error: error instanceof Error ? error.message : "Unable to create withdrawal request",
    }, 500);
  }
});

function json(body: Record<string, unknown>, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

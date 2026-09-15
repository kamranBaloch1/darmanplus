export type DiscordResult = {
  sent: boolean;
  reason?: string;
};

export async function sendDiscordWebhook({
  content,
  embeds,
}: {
  content?: string;
  embeds?: Array<Record<string, unknown>>;
}): Promise<DiscordResult> {
  const webhookUrl =
    Deno.env.get("DISCORD_MANUAL_TOPUP_WEBHOOK_URL")?.trim() ||
    Deno.env.get("DARMAN_DISCORD_WEBHOOK_URL")?.trim() ||
    "";

  if (!webhookUrl) {
    console.warn("[discord] webhook url is not set");
    return { sent: false, reason: "Discord webhook URL is not set" };
  }

  const response = await fetch(webhookUrl, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({
      username: "Darman Alerts",
      content,
      embeds,
    }),
  });

  if (response.ok) return { sent: true };

  const errorBody = await response.text();
  console.error("[discord] webhook failed", errorBody);
  return { sent: false, reason: errorBody };
}

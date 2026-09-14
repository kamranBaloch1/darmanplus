type EmailOptions = {
  to: string | string[];
  subject: string;
  text: string;
  html: string;
};

export async function sendEmail({
  to,
  subject,
  text,
  html,
}: EmailOptions): Promise<boolean> {
  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY is not set");
    return false;
  }

  const recipients = Array.isArray(to) ? to : [to];
  const cleanRecipients = recipients.map((item) => item.trim()).filter(Boolean);
  if (!cleanRecipients.length) {
    console.warn("[email] no recipients configured");
    return false;
  }

  const from = Deno.env.get("DARMAN_ALERT_FROM_EMAIL")?.trim() ||
    "Darman Alerts <onboarding@resend.dev>";

  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      "Authorization": `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      from,
      to: cleanRecipients,
      subject,
      text,
      html,
    }),
  });

  if (response.ok) return true;
  const errorBody = await response.text();
  console.error("[email] Resend failed", errorBody);
  throw new Error(`Email send failed: ${errorBody}`);
}

export function adminAlertEmails(): string[] {
  const value = Deno.env.get("ADMIN_PAYMENT_EMAIL")?.trim() ||
    Deno.env.get("DARMAN_PAYMENT_ALERT_EMAIL")?.trim() ||
    Deno.env.get("DARMAN_ADMIN_EMAILS")?.trim() ||
    "";

  return value.split(",").map((item) => item.trim()).filter(Boolean);
}

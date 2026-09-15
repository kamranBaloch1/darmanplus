type EmailOptions = {
  to: string | string[];
  subject: string;
  text: string;
  html: string;
};

export type EmailResult = {
  sent: boolean;
  reason?: string;
};

export async function sendEmail({
  to,
  subject,
  text,
  html,
}: EmailOptions): Promise<EmailResult> {
  const apiKey = Deno.env.get("RESEND_API_KEY")?.trim();
  if (!apiKey) {
    console.warn("[email] RESEND_API_KEY is not set");
    return { sent: false, reason: "RESEND_API_KEY is not set" };
  }

  const recipients = Array.isArray(to) ? to : [to];
  const cleanRecipients = recipients.map((item) => item.trim()).filter(Boolean);
  if (!cleanRecipients.length) {
    console.warn("[email] no recipients configured");
    return { sent: false, reason: "No admin email configured" };
  }

  const from = Deno.env.get("DARMAN_ALERT_FROM_EMAIL")?.trim() ||
    "onboarding@resend.dev";

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

  if (response.ok) return { sent: true };
  const errorBody = await response.text();
  console.error("[email] Resend failed", errorBody);
  return { sent: false, reason: errorBody };
}

export function adminAlertEmails(): string[] {
  const value = Deno.env.get("ADMIN_PAYMENT_EMAIL")?.trim() ||
    Deno.env.get("DARMAN_PAYMENT_ALERT_EMAIL")?.trim() ||
    Deno.env.get("DARMAN_ADMIN_EMAILS")?.trim() ||
    "";

  return value.split(",").map((item) => item.trim()).filter(Boolean);
}

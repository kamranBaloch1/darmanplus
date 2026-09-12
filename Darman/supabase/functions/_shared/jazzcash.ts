export const jsonHeaders = {
  "Content-Type": "application/json",
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

export function jsonResponse(
  body: Record<string, unknown>,
  status = 200,
): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

export function requireJazzCashConfig() {
  const merchantId = Deno.env.get("JAZZCASH_MERCHANT_ID")?.trim() ?? "";
  const password = Deno.env.get("JAZZCASH_PASSWORD")?.trim() ?? "";
  const integritySalt =
    Deno.env.get("JAZZCASH_INTEGRITY_SALT")?.trim() ?? "";
  const paymentUrl = Deno.env.get("JAZZCASH_PAYMENT_URL")?.trim() ?? "";

  if (!merchantId || !password || !integritySalt || !paymentUrl) {
    throw new Error("JazzCash merchant credentials are not configured");
  }

  const parsedPaymentUrl = new URL(paymentUrl);
  if (
    parsedPaymentUrl.protocol !== "https:" ||
    !parsedPaymentUrl.hostname.toLowerCase().endsWith("jazzcash.com.pk")
  ) {
    throw new Error("JazzCash payment URL is invalid");
  }

  return { merchantId, password, integritySalt, paymentUrl };
}

export function requireJazzCashInquiryConfig() {
  const base = requireJazzCashConfig();
  const inquiryUrl = Deno.env.get("JAZZCASH_INQUIRY_URL")?.trim() ?? "";
  if (!inquiryUrl) {
    throw new Error("JazzCash inquiry URL is not configured");
  }

  const parsedInquiryUrl = new URL(inquiryUrl);
  const officialHttps = parsedInquiryUrl.protocol === "https:" &&
    parsedInquiryUrl.hostname.toLowerCase().endsWith("jazzcash.com.pk");
  // JazzCash's published legacy sandbox inquiry endpoint is HTTP on this IP.
  // Production is still required to use the private HTTPS URL JazzCash gives
  // the approved merchant.
  const publishedSandbox = parsedInquiryUrl.protocol === "http:" &&
    parsedInquiryUrl.hostname === "119.160.80.70";
  if (!officialHttps && !publishedSandbox) {
    throw new Error("JazzCash inquiry URL is invalid");
  }

  return { ...base, inquiryUrl };
}

/// JazzCash v4.2: sort all non-empty pp* fields by ASCII field name, join the
/// values with &, prepend the integrity salt, then HMAC-SHA256 with that salt.
export async function jazzCashSecureHash(
  fields: Record<string, string>,
  integritySalt: string,
): Promise<string> {
  const values = Object.entries(fields)
    .filter(([key, value]) =>
      key.toLowerCase().startsWith("pp") &&
      key.toLowerCase() !== "pp_securehash" &&
      value.length > 0
    )
    .sort(([left], [right]) => left < right ? -1 : left > right ? 1 : 0)
    .map(([, value]) => value);

  const message = `${integritySalt}&${values.join("&")}`;
  const encoder = new TextEncoder();
  const key = await crypto.subtle.importKey(
    "raw",
    encoder.encode(integritySalt),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const signature = await crypto.subtle.sign(
    "HMAC",
    key,
    encoder.encode(message),
  );
  return [...new Uint8Array(signature)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
    .toUpperCase();
}

export function secureHashMatches(expected: string, received: string): boolean {
  const left = expected.trim().toLowerCase();
  const right = received.trim().toLowerCase();
  if (!left || left.length !== right.length) return false;
  let difference = 0;
  for (let index = 0; index < left.length; index += 1) {
    difference |= left.charCodeAt(index) ^ right.charCodeAt(index);
  }
  return difference === 0;
}

export async function sha256Hex(value: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(value),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

export function randomToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  bytes.forEach((byte) => binary += String.fromCharCode(byte));
  return btoa(binary)
    .replaceAll("+", "-")
    .replaceAll("/", "_")
    .replaceAll("=", "");
}

export function pakistanTimestamp(value: Date): string {
  const date = new Date(value.getTime() + 5 * 60 * 60 * 1000);
  return [
    date.getUTCFullYear().toString().padStart(4, "0"),
    (date.getUTCMonth() + 1).toString().padStart(2, "0"),
    date.getUTCDate().toString().padStart(2, "0"),
    date.getUTCHours().toString().padStart(2, "0"),
    date.getUTCMinutes().toString().padStart(2, "0"),
    date.getUTCSeconds().toString().padStart(2, "0"),
  ].join("");
}

export function escapeHtml(value: string): string {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

export function htmlResponse(html: string, status = 200): Response {
  return new Response(html, {
    status,
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-store, max-age=0",
      "Referrer-Policy": "no-referrer",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
    },
  });
}

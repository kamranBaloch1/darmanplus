import { createClient } from "npm:@supabase/supabase-js@2";
import {
  escapeHtml,
  htmlResponse,
  jazzCashSecureHash,
  pakistanTimestamp,
  requireJazzCashConfig,
  sha256Hex,
} from "../_shared/jazzcash.ts";

Deno.serve(async (request) => {
  if (request.method !== "GET") {
    return htmlResponse(paymentPage(
      "Payment link unavailable",
      "Open this payment from the Darman app.",
      false,
    ), 405);
  }

  try {
    const url = new URL(request.url);
    const requestId = url.searchParams.get("request_id")?.trim() ?? "";
    const checkoutToken = url.searchParams.get("token")?.trim() ?? "";
    if (!requestId || !checkoutToken) {
      return htmlResponse(paymentPage(
        "Invalid payment link",
        "Return to Darman and create a new wallet top-up.",
        false,
      ), 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const tokenHash = await sha256Hex(checkoutToken);
    const { data: topUp, error } = await admin
      .from("wallet_top_up_requests")
      .select(
        "id, user_id, amount, amount_minor, currency, status, merchant_txn_ref, expires_at",
      )
      .eq("id", requestId)
      .eq("checkout_token_hash", tokenHash)
      .maybeSingle();
    if (error) throw error;
    if (!topUp) {
      return htmlResponse(paymentPage(
        "Invalid payment link",
        "Return to Darman and create a new wallet top-up.",
        false,
      ), 404);
    }
    if (topUp.status !== "pending") {
      return htmlResponse(paymentPage(
        topUp.status === "succeeded" ? "Payment completed" : "Payment closed",
        topUp.status === "succeeded"
          ? "This amount has already been added to your Darman wallet."
          : "Return to Darman and create a new wallet top-up.",
        topUp.status === "succeeded",
      ));
    }

    const expiresAt = new Date(topUp.expires_at);
    if (expiresAt.getTime() <= Date.now()) {
      await admin.from("wallet_top_up_requests").update({
        status: "expired",
        response_message: "Payment session expired",
        updated_at: new Date().toISOString(),
      }).eq("id", topUp.id).eq("status", "pending");
      return htmlResponse(paymentPage(
        "Payment link expired",
        "Return to Darman and create a new wallet top-up.",
        false,
      ), 410);
    }

    const config = requireJazzCashConfig();
    const now = new Date();
    const callbackUrl =
      `${Deno.env.get("SUPABASE_URL")!}/functions/v1/jazzcash-payment-callback`;
    const fields: Record<string, string> = {
      pp_Version: "1.1",
      pp_TxnType: "MWALLET",
      pp_Language: "EN",
      pp_MerchantID: config.merchantId,
      pp_SubMerchantID: "",
      pp_Password: config.password,
      pp_BankID: "TBANK",
      pp_ProductID: "RETL",
      pp_TxnRefNo: topUp.merchant_txn_ref,
      pp_Amount: topUp.amount_minor.toString(),
      pp_TxnCurrency: "PKR",
      pp_TxnDateTime: pakistanTimestamp(now),
      pp_BillReference: `DARMAN-${topUp.id.slice(0, 8).toUpperCase()}`,
      pp_Description: "Darman wallet top up",
      pp_TxnExpiryDateTime: pakistanTimestamp(expiresAt),
      pp_ReturnURL: callbackUrl,
      ppmpf_1: topUp.id,
      ppmpf_2: "",
      ppmpf_3: "",
      ppmpf_4: "",
      ppmpf_5: "",
    };
    fields.pp_SecureHash = await jazzCashSecureHash(
      fields,
      config.integritySalt,
    );

    const inputs = Object.entries(fields)
      .map(([name, value]) =>
        `<input type="hidden" name="${escapeHtml(name)}" value="${escapeHtml(value)}">`
      )
      .join("\n");
    const paymentHost = new URL(config.paymentUrl).origin;
    return htmlResponse(`<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <meta name="referrer" content="no-referrer">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'unsafe-inline'; form-action ${escapeHtml(paymentHost)}; base-uri 'none'">
  <title>Opening JazzCash</title>
  <style>${pageStyles()}</style>
</head>
<body onload="document.getElementById('jazzcash-form').submit()">
  <main>
    <div class="mark">J</div>
    <h1>Opening JazzCash</h1>
    <p>Securely redirecting you to complete your wallet payment.</p>
    <form id="jazzcash-form" method="post" action="${escapeHtml(config.paymentUrl)}">
      ${inputs}
      <button type="submit">Continue to JazzCash</button>
    </form>
  </main>
</body>
</html>`);
  } catch (_) {
    return htmlResponse(paymentPage(
      "Payment unavailable",
      "JazzCash could not be opened. Return to Darman and try again.",
      false,
    ), 500);
  }
});

function paymentPage(title: string, message: string, success: boolean): string {
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>${escapeHtml(title)}</title><style>${pageStyles()}</style></head><body><main><div class="mark ${success ? "success" : ""}">${success ? "✓" : "J"}</div><h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p><a class="button" href="darman://wallet">Return to Darman</a></main></body></html>`;
}

function pageStyles(): string {
  return "*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f6f7f9;color:#0f172a;font-family:system-ui,-apple-system,sans-serif;padding:24px}main{width:min(100%,420px);background:#fff;border-radius:24px;padding:32px 24px;text-align:center;box-shadow:0 16px 50px rgba(15,23,42,.08)}.mark{width:58px;height:58px;border-radius:18px;background:#e31837;color:#fff;display:grid;place-items:center;margin:0 auto 20px;font-size:28px;font-weight:800}.mark.success{background:#16a34a}h1{font-size:24px;margin:0 0 10px}p{color:#64748b;line-height:1.5;margin:0 0 24px}.button,button{display:block;width:100%;border:0;border-radius:14px;background:#007efe;color:#fff;padding:15px;font-size:15px;font-weight:700;text-decoration:none;cursor:pointer}";
}

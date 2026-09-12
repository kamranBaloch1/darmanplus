import { createClient } from "npm:@supabase/supabase-js@2";
import {
  escapeHtml,
  htmlResponse,
  jazzCashSecureHash,
  requireJazzCashConfig,
  secureHashMatches,
} from "../_shared/jazzcash.ts";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return htmlResponse(resultPage(
      false,
      "Invalid payment response",
      "Return to Darman and check your wallet.",
    ), 405);
  }

  try {
    const formData = await request.formData();
    const fields: Record<string, string> = {};
    for (const [key, value] of formData.entries()) {
      if (typeof value === "string") fields[key] = value;
    }

    const config = requireJazzCashConfig();
    const receivedHash = fields.pp_SecureHash?.trim() ?? "";
    const calculatedHash = await jazzCashSecureHash(
      fields,
      config.integritySalt,
    );
    if (!secureHashMatches(calculatedHash, receivedHash)) {
      return htmlResponse(resultPage(
        false,
        "Payment could not be verified",
        "Your wallet was not changed. Return to Darman and contact support if money was deducted.",
      ), 400);
    }

    const merchantId = fields.pp_MerchantID?.trim() ?? "";
    const transactionRef = fields.pp_TxnRefNo?.trim() ?? "";
    const amountMinor = Number.parseInt(fields.pp_Amount?.trim() ?? "", 10);
    const responseCode = fields.pp_ResponseCode?.trim() ?? "";
    const responseMessage = fields.pp_ResponseMessage?.trim() ?? "";
    const providerReference =
      fields.pp_RetreivalReferenceNo?.trim() ??
      fields.pp_RetrievalReferenceNo?.trim() ??
      "";

    if (
      merchantId !== config.merchantId ||
      !transactionRef ||
      !Number.isSafeInteger(amountMinor) ||
      amountMinor <= 0 ||
      !responseCode
    ) {
      return htmlResponse(resultPage(
        false,
        "Invalid payment response",
        "Your wallet was not changed.",
      ), 400);
    }

    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data, error } = await admin.rpc(
      "finalize_jazzcash_wallet_top_up",
      {
        p_merchant_txn_ref: transactionRef,
        p_amount_minor: amountMinor,
        p_response_code: responseCode,
        p_response_message: responseMessage,
        p_provider_reference: providerReference,
        p_response_payload: {
          response_code: responseCode,
          response_message: responseMessage,
          provider_reference: providerReference,
          merchant_txn_ref: transactionRef,
          amount_minor: amountMinor,
        },
      },
    );
    if (error) throw error;

    const result = data as Record<string, unknown>;
    const succeeded = result.status === "succeeded";
    return htmlResponse(resultPage(
      succeeded,
      succeeded ? "Money added successfully" : "Payment not completed",
      succeeded
        ? "Your Darman wallet has been updated."
        : (responseMessage || "JazzCash did not complete this payment."),
    ));
  } catch (_) {
    return htmlResponse(resultPage(
      false,
      "Payment confirmation delayed",
      "Return to Darman and check the payment status. Your wallet will only update after verification.",
    ), 500);
  }
});

function resultPage(success: boolean, title: string, message: string): string {
  const color = success ? "#16a34a" : "#e31837";
  return `<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><meta name="referrer" content="no-referrer"><title>${escapeHtml(title)}</title><style>*{box-sizing:border-box}body{margin:0;min-height:100vh;display:grid;place-items:center;background:#f6f7f9;color:#0f172a;font-family:system-ui,-apple-system,sans-serif;padding:24px}main{width:min(100%,420px);background:#fff;border-radius:24px;padding:32px 24px;text-align:center;box-shadow:0 16px 50px rgba(15,23,42,.08)}.mark{width:62px;height:62px;border-radius:50%;background:${color};color:#fff;display:grid;place-items:center;margin:0 auto 20px;font-size:30px;font-weight:800}h1{font-size:24px;margin:0 0 10px}p{color:#64748b;line-height:1.5;margin:0 0 24px}.button{display:block;width:100%;border-radius:14px;background:#007efe;color:#fff;padding:15px;font-size:15px;font-weight:700;text-decoration:none}</style></head><body><main><div class="mark">${success ? "✓" : "!"}</div><h1>${escapeHtml(title)}</h1><p>${escapeHtml(message)}</p><a class="button" href="darman://wallet">Return to Darman</a></main></body></html>`;
}

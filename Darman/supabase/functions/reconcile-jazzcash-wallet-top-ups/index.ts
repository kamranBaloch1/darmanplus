import { createClient } from "npm:@supabase/supabase-js@2";
import {
  jazzCashSecureHash,
  requireJazzCashInquiryConfig,
} from "../_shared/jazzcash.ts";

type ClaimedTopUp = {
  request_id: string;
  merchant_txn_ref: string;
  amount_minor: number;
  provider_reference: string | null;
  created_at: string;
  reconciliation_attempts: number;
};

type ReconciliationState =
  | "pending"
  | "settled"
  | "reversed"
  | "review_required";

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  try {
    const cronSecret = request.headers.get("x-darman-cron-secret")?.trim() ?? "";
    const { data: authorized, error: authorizationError } = await admin.rpc(
      "verify_wallet_reconciliation_cron_secret",
      { p_secret: cronSecret },
    );
    if (authorizationError || authorized !== true) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const config = requireJazzCashInquiryConfig();
    const { data, error } = await admin.rpc(
      "claim_jazzcash_top_ups_for_reconciliation",
      { p_limit: 25 },
    );
    if (error) throw error;

    const topUps = (data ?? []) as ClaimedTopUp[];
    let settled = 0;
    let reversed = 0;
    let pending = 0;
    let reviewRequired = 0;

    for (const topUp of topUps) {
      let state: ReconciliationState = "pending";
      let providerStatus = "INQUIRY_PENDING";
      let providerReference = topUp.provider_reference;
      let settlementDate: string | null = null;
      let safePayload: Record<string, unknown> = {};

      try {
        const fields: Record<string, string> = {
          pp_MerchantID: config.merchantId,
          pp_Password: config.password,
          pp_TxnRefNo: topUp.merchant_txn_ref,
          pp_Version: "2.0",
        };
        fields.pp_SecureHash = await jazzCashSecureHash(
          fields,
          config.integritySalt,
        );

        const response = await fetch(config.inquiryUrl, {
          method: "POST",
          headers: {
            "Accept": "application/json",
            "Content-Type": "application/json",
          },
          body: JSON.stringify(fields),
          signal: AbortSignal.timeout(15000),
        });
        if (!response.ok) {
          throw new Error(`JazzCash inquiry returned HTTP ${response.status}`);
        }

        const payload = await response.json() as Record<string, unknown>;
        providerStatus = readString(payload, "status", "transactionStatus") ||
          "UNKNOWN";
        providerReference = readString(
          payload,
          "rrn",
          "pp_RetrievalReferenceNo",
          "pp_RetreivalReferenceNo",
        ) || providerReference;
        settlementDate = normalizeSettlementDate(
          readString(payload, "settlementDate", "pp_SettlementDate"),
        );
        state = classifyProviderState({
          providerStatus,
          settlementDate,
          attempts: topUp.reconciliation_attempts,
          createdAt: topUp.created_at,
        });
        safePayload = {
          provider_status: providerStatus,
          provider_reference: providerReference,
          settlement_date: settlementDate,
          checked_at: new Date().toISOString(),
        };
      } catch (error) {
        providerStatus = "INQUIRY_ERROR";
        state = needsManualReview(
            topUp.reconciliation_attempts,
            topUp.created_at,
          )
          ? "review_required"
          : "pending";
        safePayload = {
          provider_status: providerStatus,
          error: error instanceof Error ? error.message.slice(0, 300) : "Inquiry failed",
          checked_at: new Date().toISOString(),
        };
      }

      const { error: applyError } = await admin.rpc(
        "apply_jazzcash_reconciliation_result",
        {
          p_request_id: topUp.request_id,
          p_state: state,
          p_provider_status: providerStatus,
          p_provider_reference: providerReference,
          p_settlement_date: settlementDate,
          p_response_payload: safePayload,
        },
      );
      if (applyError) throw applyError;

      if (state === "settled") settled += 1;
      else if (state === "reversed") reversed += 1;
      else if (state === "review_required") reviewRequired += 1;
      else pending += 1;
    }

    return Response.json({
      processed: topUps.length,
      settled,
      reversed,
      pending,
      review_required: reviewRequired,
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Reconciliation failed";
    const configurationError = message.includes("not configured") ||
      message.includes("inquiry URL");
    return Response.json(
      { error: configurationError ? "JazzCash reconciliation is not configured" : message },
      { status: configurationError ? 503 : 500 },
    );
  }
});

function readString(
  payload: Record<string, unknown>,
  ...keys: string[]
): string {
  for (const key of keys) {
    const value = payload[key];
    if (value !== null && value !== undefined) {
      const text = value.toString().trim();
      if (text) return text;
    }
  }
  return "";
}

function normalizedStatus(value: string): string {
  return value.trim().toUpperCase().replaceAll(/[^A-Z0-9]+/g, "_");
}

function classifyProviderState({
  providerStatus,
  settlementDate,
  attempts,
  createdAt,
}: {
  providerStatus: string;
  settlementDate: string | null;
  attempts: number;
  createdAt: string;
}): ReconciliationState {
  const status = normalizedStatus(providerStatus);
  const reversalStates = new Set([
    "REVERSED",
    "VOIDED",
    "REFUNDED",
    "CHARGEBACK",
    "CHARGED_BACK",
  ]);
  if (reversalStates.has(status)) return "reversed";

  const settlementStates = new Set([
    "SETTLED",
    "CAPTURED",
    "COMPLETED",
    "SUCCESS",
    "SUCCESSFUL",
  ]);
  if (
    settlementDate !== null &&
    settlementStates.has(status) &&
    settlementDate <= pakistanDate(new Date())
  ) {
    return "settled";
  }

  return needsManualReview(attempts, createdAt) ? "review_required" : "pending";
}

function needsManualReview(attempts: number, createdAt: string): boolean {
  const age = Date.now() - new Date(createdAt).getTime();
  return attempts >= 20 || age >= 7 * 24 * 60 * 60 * 1000;
}

function normalizeSettlementDate(value: string): string | null {
  const digits = value.replaceAll(/[^0-9]/g, "");
  if (digits.length !== 8) return null;
  const normalized = `${digits.slice(0, 4)}-${digits.slice(4, 6)}-${digits.slice(6, 8)}`;
  return Number.isNaN(Date.parse(`${normalized}T00:00:00Z`)) ? null : normalized;
}

function pakistanDate(value: Date): string {
  const date = new Date(value.getTime() + 5 * 60 * 60 * 1000);
  return [
    date.getUTCFullYear().toString().padStart(4, "0"),
    (date.getUTCMonth() + 1).toString().padStart(2, "0"),
    date.getUTCDate().toString().padStart(2, "0"),
  ].join("-");
}

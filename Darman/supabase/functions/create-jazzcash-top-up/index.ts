import { createClient } from "npm:@supabase/supabase-js@2";
import {
  jsonHeaders,
  jsonResponse,
  randomToken,
  requireJazzCashConfig,
  sha256Hex,
} from "../_shared/jazzcash.ts";

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: jsonHeaders });
  }
  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed" }, 405);
  }

  try {
    const authorization = request.headers.get("Authorization")?.trim() ?? "";
    if (!authorization) {
      return jsonResponse({ error: "Authentication required" }, 401);
    }

    const userClient = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: authData, error: authError } = await userClient.auth.getUser();
    if (authError || !authData.user) {
      return jsonResponse({ error: "Authentication required" }, 401);
    }

    // Refuse to create orphan payment requests until all merchant secrets exist.
    requireJazzCashConfig();

    const body = await request.json().catch(() => ({}));
    const amount = Number((body as Record<string, unknown>).amount);
    if (!Number.isSafeInteger(amount)) {
      return jsonResponse({ error: "Enter a whole-number amount in PKR" }, 400);
    }

    const checkoutToken = randomToken();
    const checkoutTokenHash = await sha256Hex(checkoutToken);
    const { data, error } = await userClient.rpc(
      "create_wallet_top_up_request",
      {
        p_amount: amount,
        p_checkout_token_hash: checkoutTokenHash,
      },
    );
    if (error) throw error;

    const result = data as Record<string, unknown>;
    const requestId = result.request_id?.toString() ?? "";
    if (!requestId) throw new Error("Payment request could not be created");

    const projectUrl = Deno.env.get("SUPABASE_URL")!;
    const checkoutUrl = new URL(
      `${projectUrl}/functions/v1/jazzcash-checkout`,
    );
    checkoutUrl.searchParams.set("request_id", requestId);
    checkoutUrl.searchParams.set("token", checkoutToken);

    return jsonResponse({
      request_id: requestId,
      status: result.status,
      amount: result.amount,
      currency: result.currency,
      expires_at: result.expires_at,
      checkout_url: checkoutUrl.toString(),
    });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Payment failed";
    const configurationError = message.includes("not configured") ||
      message.includes("payment URL");
    return jsonResponse(
      { error: configurationError ? "JazzCash is not available yet" : message },
      configurationError ? 503 : 400,
    );
  }
});

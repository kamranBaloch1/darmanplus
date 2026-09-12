import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return new Response(
      JSON.stringify({ error: "Method Not Allowed" }),
      {
        status: 405,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  }

  const authHeader = req.headers.get("Authorization");

  if (!authHeader) {
    return new Response(
      JSON.stringify({ error: "Missing authorization" }),
      {
        status: 401,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  }

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    {
      global: {
        headers: {
          Authorization: authHeader,
        },
      },
    },
  );

  // Verify logged-in user
  const {
    data: { user },
    error: userError,
  } = await supabase.auth.getUser();

  if (userError || !user) {
    return new Response(
      JSON.stringify({ error: "Unauthorized" }),
      {
        status: 401,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  }

  try {
    const body = await req.json();

    const receiptUrl = String(
      body.receipt_url ?? "",
    ).trim();

    // Receipt is required
    if (!receiptUrl) {
      return new Response(
        JSON.stringify({
          error: "Payment receipt is required",
        }),
        {
          status: 400,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    // Create manual top-up request.
    // Amount is intentionally NOT provided.
    // The Darman team will determine the amount from the receipt.
    const { data, error } = await supabase.rpc(
      "create_manual_wallet_top_up",
      {
        p_receipt_url: receiptUrl,
      },
    );

    if (error) {
      console.error("RPC ERROR:", {
        code: error.code,
        message: error.message,
        details: error.details,
        hint: error.hint,
      });

      return new Response(
        JSON.stringify({
          error: error.message,
          code: error.code,
          details: error.details,
          hint: error.hint,
        }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    if (!data) {
      return new Response(
        JSON.stringify({
          error: "Top-up request was not created",
        }),
        {
          status: 500,
          headers: {
            "Content-Type": "application/json",
          },
        },
      );
    }

    console.log(
      `Manual top-up created successfully for user ${user.id}`,
    );

    return new Response(
      JSON.stringify({
        top_up: data,
      }),
      {
        status: 200,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  } catch (error) {
    console.error("MANUAL TOP-UP ERROR:", error);

    return new Response(
      JSON.stringify({
        error: error instanceof Error
          ? error.message
          : "Unable to create top-up",
      }),
      {
        status: 500,
        headers: {
          "Content-Type": "application/json",
        },
      },
    );
  }
});
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { adminAlertEmails, sendEmail } from "../_shared/email.ts";

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

    let emailAlert = {
      sent: false,
      reason: "Email was not attempted",
    };

    try {
      emailAlert = await notifyAdminAboutManualTopUp({
        topUp: data,
        receiptUrl,
        userId: user.id,
      });
    } catch (emailError) {
      console.error("MANUAL TOP-UP EMAIL ERROR:", emailError);
    }

    return new Response(
      JSON.stringify({
        top_up: data,
        email_alert: emailAlert,
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

async function notifyAdminAboutManualTopUp({
  topUp,
  receiptUrl,
  userId,
}: {
  topUp: Record<string, unknown>;
  receiptUrl: string;
  userId: string;
}): Promise<{ sent: boolean; reason?: string }> {
  const to = adminAlertEmails();
  if (!to.length) {
    console.warn("MANUAL TOP-UP EMAIL SKIPPED: no admin recipient configured");
    return { sent: false, reason: "No admin email configured" };
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const { data: patient } = await admin
    .from("users")
    .select("name, phone, email")
    .eq("uid", userId)
    .maybeSingle();

  const patientName = patient?.name?.toString().trim() || "Unknown patient";
  const phone = patient?.phone?.toString().trim() || "No phone";
  const email = patient?.email?.toString().trim() || "";
  const requestId = topUp?.id?.toString() || "new request";

  const result = await sendEmail({
    to,
    subject: "New manual wallet top-up request",
    text:
      `A patient submitted a manual wallet top-up receipt.\n\nPatient: ${patientName}\nPhone: ${phone}\nEmail: ${email}\nRequest ID: ${requestId}\nReceipt: ${receiptUrl}\n\nOpen Darman Admin to verify the payment.`,
    html:
      `<h2>New manual wallet top-up request</h2><p>A patient submitted a receipt for review.</p><ul><li><strong>Patient:</strong> ${escapeHtml(patientName)}</li><li><strong>Phone:</strong> ${escapeHtml(phone)}</li><li><strong>Email:</strong> ${escapeHtml(email || "-")}</li><li><strong>Request ID:</strong> ${escapeHtml(requestId)}</li></ul><p><a href="${escapeHtml(receiptUrl)}">Open receipt</a></p><p>Open Darman Admin to verify the payment.</p>`,
  });
  console.log("MANUAL TOP-UP EMAIL RESULT:", { result, to, requestId });
  return result;
}

function escapeHtml(value: string) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

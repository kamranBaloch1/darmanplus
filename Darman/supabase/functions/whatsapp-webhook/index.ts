import { serve } from "https://deno.land/std@0.168.0/http/server.ts";

const VERIFY_TOKEN = Deno.env.get("WHATSAPP_WEBHOOK_VERIFY_TOKEN");

serve(async (req) => {
  const url = new URL(req.url);

  // --------------------------------------------------
  // 1. META WEBHOOK VERIFICATION
  // --------------------------------------------------
  if (req.method === "GET") {
    const mode = url.searchParams.get("hub.mode");
    const token = url.searchParams.get("hub.verify_token");
    const challenge = url.searchParams.get("hub.challenge");

    console.log("[whatsapp-webhook] Verification request", {
      mode,
      tokenProvided: !!token,
      challengeProvided: !!challenge,
    });

    if (
      mode === "subscribe" &&
      token &&
      VERIFY_TOKEN &&
      token === VERIFY_TOKEN
    ) {
      console.log("[whatsapp-webhook] Verification successful");

      return new Response(challenge, {
        status: 200,
        headers: {
          "Content-Type": "text/plain",
        },
      });
    }

    console.error("[whatsapp-webhook] Verification failed");

    return new Response("Forbidden", {
      status: 403,
    });
  }

  // --------------------------------------------------
  // 2. RECEIVE WHATSAPP EVENTS
  // --------------------------------------------------
  if (req.method === "POST") {
    try {
      const body = await req.json();

      console.log(
        "[whatsapp-webhook] Incoming webhook:",
        JSON.stringify(body)
      );

      // WhatsApp Business Account event
      if (body.object === "whatsapp_business_account") {
        const entries = body.entry ?? [];

        for (const entry of entries) {
          const changes = entry.changes ?? [];

          for (const change of changes) {
            const value = change.value ?? {};

            // ------------------------------------------
            // OUTGOING MESSAGE STATUS
            // ------------------------------------------
            const statuses = value.statuses ?? [];

            for (const status of statuses) {
              console.log("[whatsapp-webhook] MESSAGE STATUS", {
                id: status.id,
                status: status.status,
                timestamp: status.timestamp,
                recipient_id: status.recipient_id,
                conversation: status.conversation,
                pricing: status.pricing,
                errors: status.errors,
              });
            }

            // ------------------------------------------
            // INCOMING MESSAGES
            // ------------------------------------------
            const messages = value.messages ?? [];

            for (const message of messages) {
              console.log("[whatsapp-webhook] INCOMING MESSAGE", {
                id: message.id,
                from: message.from,
                type: message.type,
                timestamp: message.timestamp,
              });
            }
          }
        }
      }

      // Meta expects a successful response
      return new Response("EVENT_RECEIVED", {
        status: 200,
        headers: {
          "Content-Type": "text/plain",
        },
      });
    } catch (error) {
      console.error("[whatsapp-webhook] POST error:", error);

      return new Response("EVENT_RECEIVED", {
        status: 200,
        headers: {
          "Content-Type": "text/plain",
        },
      });
    }
  }

  return new Response("Method Not Allowed", {
    status: 405,
  });
});
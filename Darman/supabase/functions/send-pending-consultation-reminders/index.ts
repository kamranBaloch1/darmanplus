import { createClient } from "npm:@supabase/supabase-js@2";
import { sendPushToUser } from "../_shared/push.ts";

type DoctorReminder = {
  doctor_id: string;
  request_count: number;
  booking_ids: string[];
};

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  try {
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const secret = request.headers.get("x-darman-cron-secret")?.trim() ?? "";
    const { data: authorized, error: authError } = await admin.rpc(
      "verify_follow_up_reminder_cron_secret",
      { p_secret: secret },
    );
    if (authError || authorized !== true) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { data, error } = await admin.rpc(
      "claim_pending_consultation_request_reminders",
    );
    if (error) throw error;

    let doctorsNotified = 0;
    let requestsIncluded = 0;
    for (const reminder of (data ?? []) as DoctorReminder[]) {
      const count = Number(reminder.request_count);
      const result = await sendPushToUser({
        admin,
        userId: reminder.doctor_id,
        title: "Consultation requests waiting",
        body: count === 1
          ? "You have 1 consultation request waiting for your response"
          : `You have ${count} consultation requests waiting for your response`,
        ttl: "1800s",
        data: {
          type: "pending_consultation_reminder",
          request_count: String(count),
        },
      });

      if (result.sent > 0) {
        doctorsNotified += 1;
        requestsIncluded += count;
      } else {
        await admin.rpc("release_pending_consultation_request_reminders", {
          p_booking_ids: reminder.booking_ids,
        });
      }
    }

    return Response.json({
      doctors_notified: doctorsNotified,
      requests_included: requestsIncluded,
    });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Reminder failed" },
      { status: 500 },
    );
  }
});

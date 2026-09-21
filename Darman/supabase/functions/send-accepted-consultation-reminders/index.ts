import { createClient } from "npm:@supabase/supabase-js@2";
import { sendPushToUser } from "../_shared/push.ts";

type DoctorReminder = {
  doctor_id: string;
  consultation_count: number;
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
      "claim_accepted_consultation_reminders",
    );
    if (error) throw error;

    let doctorsNotified = 0;
    let consultationsIncluded = 0;
    for (const reminder of (data ?? []) as DoctorReminder[]) {
      const count = Number(reminder.consultation_count);
      const result = await sendPushToUser({
        admin,
        userId: reminder.doctor_id,
        title: "Consultation waiting to start",
        body: count === 1
          ? "You have 1 accepted consultation waiting to be started."
          : `You have ${count} accepted consultations waiting to be started.`,
        ttl: "900s",
        data: {
          type: "accepted_consultation_reminder",
          consultation_count: String(count),
        },
      });

      if (result.sent > 0) {
        doctorsNotified += 1;
        consultationsIncluded += count;
      } else {
        await admin.rpc("release_accepted_consultation_reminders", {
          p_booking_ids: reminder.booking_ids,
        });
      }
    }

    return Response.json({
      doctors_notified: doctorsNotified,
      consultations_included: consultationsIncluded,
    });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Reminder failed" },
      { status: 500 },
    );
  }
});

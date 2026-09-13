import { createClient } from "npm:@supabase/supabase-js@2";
import { sendPushToUser } from "../_shared/push.ts";

type DueFollowUp = {
  booking_id: string;
  patient_id: string;
  doctor_id: string;
  follow_up_date: string;
  patient_notified_at: string | null;
  doctor_notified_at: string | null;
};

type Recipient = {
  userId: string;
  title: string;
  body: string;
  type: "patient" | "doctor";
};

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return Response.json({ error: "Method not allowed" }, { status: 405 });
  }

  try {
    const cronSecret = request.headers.get("x-darman-cron-secret")?.trim() ?? "";
    const admin = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    );
    const { data: authorized, error: authorizationError } = await admin.rpc(
      "verify_follow_up_reminder_cron_secret",
      { p_secret: cronSecret },
    );
    if (authorizationError || authorized !== true) {
      return Response.json({ error: "Unauthorized" }, { status: 401 });
    }

    const { data, error } = await admin.rpc(
      "claim_due_consultation_follow_up_notifications",
    );
    if (error) throw error;

    const dueFollowUps = (data ?? []) as DueFollowUp[];
    if (!dueFollowUps.length) {
      return Response.json({ processed: 0, patient_sent: 0, doctor_sent: 0 });
    }

    let patientSentCount = 0;
    let doctorSentCount = 0;

    for (const followUp of dueFollowUps) {
      let patientSent = followUp.patient_notified_at !== null;
      let doctorSent = followUp.doctor_notified_at !== null;

      try {
        const [{ data: doctor }, { data: patient }] = await Promise.all([
          admin.from("users").select("name").eq("uid", followUp.doctor_id)
            .maybeSingle(),
          admin.from("users").select("name").eq("uid", followUp.patient_id)
            .maybeSingle(),
        ]);
        const doctorName = doctor?.name?.trim() || "your doctor";
        const patientName = patient?.name?.trim() || "Your patient";

        const recipients: Recipient[] = [];
        if (!patientSent) {
          recipients.push({
            userId: followUp.patient_id,
            title: "Your follow-up is today",
            body:
              `Your free follow-up chat with ${doctorName} is open today.`,
            type: "patient",
          });
        }
        if (!doctorSent) {
          recipients.push({
            userId: followUp.doctor_id,
            title: "Patient follow-up today",
            body: `${patientName}'s follow-up chat is open today.`,
            type: "doctor",
          });
        }

        for (const recipient of recipients) {
          const sent = await sendToUser({
            admin,
            followUp,
            recipient,
            doctorName,
            patientName,
          });
          if (recipient.type === "patient") {
            patientSent = sent;
            if (sent) patientSentCount += 1;
          } else {
            doctorSent = sent;
            if (sent) doctorSentCount += 1;
          }
        }
      } finally {
        const { error: finishError } = await admin.rpc(
          "finish_consultation_follow_up_notification",
          {
            p_booking_id: followUp.booking_id,
            p_patient_sent: patientSent,
            p_doctor_sent: doctorSent,
          },
        );
        if (finishError) throw finishError;
      }
    }

    return Response.json({
      processed: dueFollowUps.length,
      patient_sent: patientSentCount,
      doctor_sent: doctorSentCount,
    });
  } catch (error) {
    return Response.json(
      { error: error instanceof Error ? error.message : "Reminder failed" },
      { status: 500 },
    );
  }
});

async function sendToUser({
  admin,
  followUp,
  recipient,
  doctorName,
  patientName,
}: {
  admin: ReturnType<typeof createClient>;
  followUp: DueFollowUp;
  recipient: Recipient;
  doctorName: string;
  patientName: string;
}): Promise<boolean> {
  const result = await sendPushToUser({
    admin,
    userId: recipient.userId,
    title: recipient.title,
    body: recipient.body,
    ttl: "86400s",
    data: {
      type: "consultation_follow_up_due",
      recipient_type: recipient.type,
      booking_id: followUp.booking_id,
      doctor_id: followUp.doctor_id,
      patient_id: followUp.patient_id,
      doctor_name: doctorName,
      patient_name: patientName,
      follow_up_date: followUp.follow_up_date,
    },
  });

  return result.sent > 0;
}

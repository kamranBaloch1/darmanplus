import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { RtcRole, RtcTokenBuilder } from "npm:agora-token@2.0.3";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

Deno.serve(async (request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: cors });
  try {
    const authorization = request.headers.get("Authorization");
    if (!authorization) throw new Error("Authentication required");
    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: authorization } } },
    );
    const { data: { user }, error: authError } = await supabase.auth.getUser();
    if (authError || !user) throw new Error("Authentication required");
    const { booking_id } = await request.json();
    if (!booking_id) throw new Error("booking_id is required");
    const { data: booking, error } = await supabase
      .from("bookings")
      .select(
        "id, patient_id, doctor_id, status, follow_up_date, follow_up_ended_at",
      )
      .eq("id", booking_id)
      .single();
    if (error || !booking) throw new Error("Booking not found");
    if (user.id !== booking.patient_id && user.id !== booking.doctor_id) throw new Error("Access denied");
    const pakistanDateParts = new Intl.DateTimeFormat("en", {
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
      timeZone: "Asia/Karachi",
    }).formatToParts(new Date());
    const pakistanDateValues = Object.fromEntries(
      pakistanDateParts.map((part) => [part.type, part.value]),
    );
    const pakistanDate =
      `${pakistanDateValues.year}-${pakistanDateValues.month}-${pakistanDateValues.day}`;
    const followUpOpen = booking.status === "completed" &&
      booking.follow_up_date &&
      booking.follow_up_date <= pakistanDate &&
      !booking.follow_up_ended_at;
    if (booking.status !== "inProgress" && !followUpOpen) {
      throw new Error("The consultation chat is not open for calls");
    }

    const appId = Deno.env.get("AGORA_APP_ID");
    const certificate = Deno.env.get("AGORA_APP_CERTIFICATE");
    if (!appId || !certificate) throw new Error("Agora is not configured");
    const channelName = `consultation_${booking.id.replaceAll("-", "")}`;
    const uid = stableUid(user.id);
    const expiresIn = 3600;
    const expiresAtSeconds = Math.floor(Date.now() / 1000) + expiresIn;
    const token = RtcTokenBuilder.buildTokenWithUid(
      appId, certificate, channelName, uid, RtcRole.PUBLISHER,
      expiresIn, expiresIn,
    );
    return Response.json({
      app_id: appId,
      channel_name: channelName,
      uid,
      token,
      expires_at: new Date(expiresAtSeconds * 1000).toISOString(),
    }, { headers: cors });
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Request failed" }, { status: 400, headers: cors });
  }
});

function stableUid(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0) || 1;
}

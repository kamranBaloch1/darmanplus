import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const adminEmails = new Set(
  (process.env.DARMAN_ADMIN_EMAILS ?? "")
    .split(",")
    .map((email) => email.trim().toLowerCase())
    .filter(Boolean),
);

async function adminClient(request: NextRequest) {
  if (!url || !service) return null;
  const client = createClient(url, service, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data, error } = await client.auth.getUser(token);
  if (error || !data.user?.email || !adminEmails.has(data.user.email.toLowerCase())) {
    return null;
  }
  return client;
}

export async function GET(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> },
) {
  const client = await adminClient(request);
  if (!client) {
    return NextResponse.json({ error: "You are not authorized to access Darman Admin." }, { status: 403 });
  }

  const { id } = await params;
  const { data: doctor, error: doctorError } = await client
    .from("users")
    .select("uid,name,email,is_email_verified,phone,is_phone_verified,role,profile_image,is_profile_completed,gender,date_of_birth,title,specialization,qualification,medical_license_number,experience_years,consultation_fee,bio,intro_video_url,doctor_documents,is_doctor_verified,is_available,doctor_rating,doctor_review_count,doctor_completed_consultation_count,wallet_balance,wallet_reserved_balance,wallet_recovery_due,created_at,updated_at")
    .eq("uid", id)
    .eq("role", "doctor")
    .single();

  if (doctorError) {
    return NextResponse.json({ error: doctorError.code === "PGRST116" ? "Doctor not found." : doctorError.message }, { status: doctorError.code === "PGRST116" ? 404 : 500 });
  }

  const [bookingsResult, ratingsResult, walletResult] = await Promise.all([
    client
      .from("bookings")
      .select("id,patient_id,status,consultation_fee,gross_fee,commission_amount,doctor_earning,created_at,accepted_at,started_at,completed_at,cancelled_at,cancellation_reason,follow_up_date,follow_up_ended_at")
      .eq("doctor_id", id)
      .order("created_at", { ascending: false })
      .limit(100),
    client
      .from("consultation_ratings")
      .select("id,booking_id,patient_id,rating,review,created_at")
      .eq("doctor_id", id)
      .order("created_at", { ascending: false })
      .limit(100),
    client
      .from("wallet_transactions")
      .select("id,booking_id,transaction_type,amount,balance_after,description,created_at")
      .eq("user_id", id)
      .order("created_at", { ascending: false })
      .limit(50),
  ]);

  if (bookingsResult.error || ratingsResult.error || walletResult.error) {
    return NextResponse.json({ error: bookingsResult.error?.message ?? ratingsResult.error?.message ?? walletResult.error?.message ?? "Could not load doctor details." }, { status: 500 });
  }

  const peopleIds = [...new Set([...(bookingsResult.data ?? []).map((booking) => booking.patient_id), ...(ratingsResult.data ?? []).map((rating) => rating.patient_id)])];
  const { data: people, error: peopleError } = peopleIds.length
    ? await client.from("users").select("uid,name,profile_image,phone").in("uid", peopleIds)
    : { data: [], error: null };
  if (peopleError) return NextResponse.json({ error: peopleError.message }, { status: 500 });

  const personById = new Map((people ?? []).map((person) => [person.uid, person]));
  const documents = (doctor.doctor_documents ?? []).map((path: string) => ({
    path,
    url: client.storage.from("doctor-documents").getPublicUrl(path).data.publicUrl,
  }));

  return NextResponse.json({
    doctor: { ...doctor, documents },
    bookings: (bookingsResult.data ?? []).map((booking) => ({ ...booking, patient: personById.get(booking.patient_id) ?? null })),
    ratings: (ratingsResult.data ?? []).map((rating) => ({ ...rating, patient: personById.get(rating.patient_id) ?? null })),
    transactions: walletResult.data ?? [],
  });
}

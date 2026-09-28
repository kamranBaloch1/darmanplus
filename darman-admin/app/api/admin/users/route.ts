import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const emails = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map((value) => value.trim().toLowerCase()).filter(Boolean));
const userFields = "uid,name,email,phone,role,profile_image,specialization,title,experience_years,medical_license_number,doctor_documents,is_profile_completed,is_doctor_verified,is_available,created_at";

async function admin(request: NextRequest) {
  if (!url || !service) return null;
  const client = createClient(url, service, { auth: { persistSession: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data } = await client.auth.getUser(token);
  return data.user?.email && emails.has(data.user.email.toLowerCase()) ? client : null;
}

export async function GET(request: NextRequest) {
  const client = await admin(request);
  if (!client) return NextResponse.json({ error: "You are not authorized to access Darman Admin." }, { status: 403 });

  const scope = request.nextUrl.searchParams.get("scope") ?? "overview";
  const page = Math.max(1, Number(request.nextUrl.searchParams.get("page")) || 1);
  const pageSize = Math.min(50, Math.max(10, Number(request.nextUrl.searchParams.get("pageSize")) || 24));
  const search = (request.nextUrl.searchParams.get("q") ?? "").trim().replace(/[,%()]/g, " ");
  const from = (page - 1) * pageSize;
  const to = from + pageSize - 1;

  const count = (role: "doctor" | "patient", verified?: boolean, available?: boolean, incomplete?: boolean) => {
    let query = client.from("users").select("uid", { count: "exact", head: true }).eq("role", role);
    if (verified !== undefined) query = query.eq("is_doctor_verified", verified);
    if (available !== undefined) query = query.eq("is_available", available);
    if (incomplete !== undefined) query = query.eq("is_profile_completed", !incomplete);
    return query;
  };

  const [patientCount, verifiedCount, pendingCount, availableCount, incompleteCount] = await Promise.all([
    count("patient"), count("doctor", true), count("doctor", false), count("doctor", true, true), count("doctor", true, undefined, true),
  ]);
  const stats = {
    patients: patientCount.count ?? 0,
    verifiedDoctors: verifiedCount.count ?? 0,
    pendingDoctors: pendingCount.count ?? 0,
    availableDoctors: availableCount.count ?? 0,
    incompleteDoctors: incompleteCount.count ?? 0,
  };

  let doctors: any[] = [], patients: any[] = [], consultations: any[] = [], total = 0;
  if (["doctors", "verification", "patients"].includes(scope)) {
    const role = scope === "patients" ? "patient" : "doctor";
    let query = client.from("users").select(userFields, { count: "exact" }).eq("role", role).order("created_at", { ascending: false }).range(from, to);
    if (scope === "doctors") query = query.eq("is_doctor_verified", true);
    if (scope === "verification") query = query.eq("is_doctor_verified", false);
    if (search) query = query.or(`name.ilike.%${search}%,email.ilike.%${search}%,phone.ilike.%${search}%`);
    const { data, error, count: rowCount } = await query;
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    total = rowCount ?? 0;
    if (role === "patient") patients = data ?? []; else doctors = data ?? [];
  } else if (["consultations", "followups"].includes(scope)) {
    let query = client.from("bookings").select("id,doctor_id,patient_id,status,consultation_fee,created_at,completed_at,follow_up_date,admin_refunded_at", { count: "exact" }).order("created_at", { ascending: false }).range(from, to);
    if (scope === "followups") query = query.not("follow_up_date", "is", null);
    const { data: bookings, error, count: rowCount } = await query;
    if (error) return NextResponse.json({ error: error.message }, { status: 500 });
    total = rowCount ?? 0;
    const ids = [...new Set((bookings ?? []).flatMap((booking) => [booking.doctor_id, booking.patient_id]).filter(Boolean))];
    const { data: people } = ids.length ? await client.from("users").select("uid,name,email,phone,role,profile_image,specialization").in("uid", ids) : { data: [] };
    const byId = new Map((people ?? []).map((person) => [person.uid, person]));
    consultations = (bookings ?? []).map((booking) => ({ ...booking, doctor: byId.get(booking.doctor_id) ?? null, patient: byId.get(booking.patient_id) ?? null }));
  } else {
    const [{ data: doctorRows }, { data: patientRows }, { data: bookings, count: bookingCount }] = await Promise.all([
      client.from("users").select(userFields).eq("role", "doctor").order("created_at", { ascending: false }).limit(8),
      client.from("users").select(userFields).eq("role", "patient").order("created_at", { ascending: false }).limit(8),
      client.from("bookings").select("id,doctor_id,patient_id,status,consultation_fee,created_at,completed_at,follow_up_date,admin_refunded_at", { count: "exact" }).order("created_at", { ascending: false }).limit(20),
    ]);
    doctors = doctorRows ?? []; patients = patientRows ?? []; total = bookingCount ?? 0;
    const byId = new Map([...doctors, ...patients].map((person) => [person.uid, person]));
    consultations = (bookings ?? []).map((booking) => ({ ...booking, doctor: byId.get(booking.doctor_id) ?? null, patient: byId.get(booking.patient_id) ?? null }));
  }

  return NextResponse.json({ doctors, patients, consultations, stats, pagination: { page, pageSize, total, totalPages: Math.max(1, Math.ceil(total / pageSize)) } });
}

import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const service = process.env.SUPABASE_SERVICE_ROLE_KEY;
const financeExcludedDoctors = new Set([
  "cf38b76d-fc43-4ac1-9dc0-bb2f514c8131",
  "9b9dd1ed-c6a2-459a-9035-a209f350c0b8",
]);
const financeExcludedPatients = new Set([
  "364705c0-2319-468d-8871-d17bb2a33c25",
  "5827fa6c-1c22-47db-bc7e-18b241f6ec8a",
]);
const financeExcludedWalletUsers = new Set([
  ...financeExcludedDoctors,
  ...financeExcludedPatients,
]);
const admins = new Set(
  (process.env.DARMAN_ADMIN_EMAILS ?? "")
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean),
);

export async function GET(request: NextRequest) {
  if (!url || !service) {
    return NextResponse.json({ error: "Admin server is not configured." }, { status: 500 });
  }

  const client = createClient(url, service, { auth: { persistSession: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data: auth } = await client.auth.getUser(token);
  if (!auth.user?.email || !admins.has(auth.user.email.toLowerCase())) {
    return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  }

  const from = request.nextUrl.searchParams.get("from");
  const to = request.nextUrl.searchParams.get("to");
  let transactionQuery = client
    .from("wallet_transactions")
    .select("id,user_id,booking_id,transaction_type,amount,description,created_at")
    .in("transaction_type", ["wallet_top_up", "consultation_payment", "doctor_earning", "platform_commission"])
    .order("created_at", { ascending: false });
  if (from) transactionQuery = transactionQuery.gte("created_at", from);
  if (to) transactionQuery = transactionQuery.lte("created_at", to);

  const [{ data: transactions, error: transactionError }, { data: users, error: userError }, { data: testBookings, error: bookingError }] =
    await Promise.all([
      transactionQuery.limit(10000),
      client
        .from("users")
        .select("uid,name,email,role,profile_image,wallet_balance,wallet_reserved_balance")
        .in("role", ["patient", "doctor"])
        .limit(10000),
      client
        .from("bookings")
        .select("id")
        .in("doctor_id", [...financeExcludedDoctors])
        .limit(10000),
    ]);

  if (transactionError || userError || bookingError) {
    return NextResponse.json(
      { error: transactionError?.message ?? userError?.message ?? bookingError?.message ?? "Finance data could not be loaded." },
      { status: 500 },
    );
  }

  const excludedBookings = new Set((testBookings ?? []).map((booking) => booking.id));
  const rows = (transactions ?? []).filter(
    (row) =>
      !excludedBookings.has(row.booking_id ?? "") &&
      !(
        row.transaction_type === "wallet_top_up" &&
        financeExcludedWalletUsers.has(row.user_id ?? "")
      ),
  );
  const people = (users ?? []).filter(
    (user) => !financeExcludedWalletUsers.has(user.uid),
  );
  const topUps = rows.filter((row) => row.transaction_type === "wallet_top_up");
  const commissions = rows.filter((row) => row.transaction_type === "platform_commission");
  const consultationPayments = rows.filter((row) => row.transaction_type === "consultation_payment");
  const doctorEarnings = rows.filter((row) => row.transaction_type === "doctor_earning");
  const doctors = people
    .filter((user) => user.role === "doctor")
    .map((user) => ({
      id: user.uid,
      name: user.name,
      email: user.email,
      profileImage: user.profile_image,
      unpaid: Number(user.wallet_balance ?? 0),
    }))
    .filter((doctor) => doctor.unpaid > 0)
    .sort((a, b) => b.unpaid - a.unpaid);
  const patients = people.filter((user) => user.role === "patient");
  const patientFunds = patients
    .map((patient) => ({
      id: patient.uid,
      name: patient.name,
      email: patient.email,
      profileImage: patient.profile_image,
      available: Number(patient.wallet_balance ?? 0),
      reserved: Number(patient.wallet_reserved_balance ?? 0),
      total:
        Number(patient.wallet_balance ?? 0) +
        Number(patient.wallet_reserved_balance ?? 0),
    }))
    .filter((patient) => patient.total > 0)
    .sort((a, b) => b.total - a.total);
  const peopleById = new Map(people.map((user) => [user.uid, user]));
  const doctorPayable = doctors.reduce((sum, doctor) => sum + doctor.unpaid, 0);
  const patientAvailable = patients.reduce((sum, patient) => sum + Number(patient.wallet_balance ?? 0), 0);
  const patientReserved = patients.reduce((sum, patient) => sum + Number(patient.wallet_reserved_balance ?? 0), 0);
  const grossConsultations = consultationPayments.reduce((sum, row) => sum + Math.abs(Number(row.amount ?? 0)), 0);
  const revenue = commissions.reduce((sum, row) => sum + Number(row.amount ?? 0), 0);

  return NextResponse.json({
    summary: {
      topUps: topUps.reduce((sum, row) => sum + Number(row.amount ?? 0), 0),
      topUpCount: topUps.length,
      revenue,
      grossConsultations,
      consultationCount: consultationPayments.length,
      doctorEarnings: doctorEarnings.reduce((sum, row) => sum + Number(row.amount ?? 0), 0),
      effectiveCommissionRate: grossConsultations > 0 ? (revenue / grossConsultations) * 100 : 0,
      doctorPayable,
      patientFunds: patientAvailable + patientReserved,
      patientAvailable,
      patientReserved,
      patientFundHolders: patients.filter(
        (patient) =>
          Number(patient.wallet_balance ?? 0) +
            Number(patient.wallet_reserved_balance ?? 0) >
          0,
      ).length,
      reservedPatientCount: patients.filter(
        (patient) => Number(patient.wallet_reserved_balance ?? 0) > 0,
      ).length,
      totalLiabilities: patientAvailable + patientReserved + doctorPayable,
    },
    doctors,
    patientFunds,
    recentTopUps: topUps.slice(0, 50),
    recentActivity: rows.slice(0, 50).map((row) => ({
      ...row,
      userName: row.user_id ? peopleById.get(row.user_id)?.name ?? null : null,
    })),
  });
}

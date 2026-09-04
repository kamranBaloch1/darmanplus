"use client";

import { useParams, useRouter } from "next/navigation";
import { useEffect, useState } from "react";
import { createClient } from "@supabase/supabase-js";
import DoctorDetailsDialog from "../../components/doctor-details-dialog";

const supabase = process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
  ? createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY)
  : null;

export default function DoctorPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [token, setToken] = useState("");
  useEffect(() => { supabase?.auth.getSession().then(({ data }) => setToken(data.session?.access_token ?? "")); }, []);
  if (!token) return null;

  async function updateVerification(method: "PATCH" | "DELETE") {
    const response = await fetch(`/api/admin/doctors/${id}/verify`, { method, headers: { Authorization: `Bearer ${token}` } });
    const result = await response.json();
    if (!response.ok) throw Error(result.error ?? "Unable to update doctor verification.");
  }

  return <DoctorDetailsDialog
    doctorId={id}
    token={token}
    onClose={() => router.push("/doctors")}
    onVerified={() => updateVerification("PATCH")}
    onUnverified={() => updateVerification("DELETE")}
  />;
}

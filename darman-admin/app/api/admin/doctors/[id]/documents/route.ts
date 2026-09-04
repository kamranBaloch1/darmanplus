import { NextRequest, NextResponse } from "next/server";
import { createClient } from "@supabase/supabase-js";

const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
const serviceKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
const admins = new Set((process.env.DARMAN_ADMIN_EMAILS ?? "").split(",").map(value => value.trim().toLowerCase()).filter(Boolean));

async function admin(request: NextRequest) {
  if (!url || !serviceKey) return null;
  const client = createClient(url, serviceKey, { auth: { persistSession: false, autoRefreshToken: false } });
  const token = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  const { data } = await client.auth.getUser(token);
  return data.user?.email && admins.has(data.user.email.toLowerCase()) ? { client, email: data.user.email } : null;
}

export async function PATCH(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const access = await admin(request);
  if (!access) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  const { id } = await params;
  const { path, status, reason } = await request.json();
  if (!path || !status) return NextResponse.json({ error: "Document review details are required." }, { status: 400 });
  const { error } = await access.client.from("admin_doctor_document_reviews").upsert({ doctor_id: id, document_path: path, status, reason: reason || null, reviewed_by: access.email, reviewed_at: new Date().toISOString() });
  if (error) return NextResponse.json({ error: error.message }, { status: 500 });
  await access.client.from("admin_doctor_audit_log").insert({ doctor_id: id, admin_email: access.email, action: `document_${status}`, detail: { path, reason } });
  return NextResponse.json({ ok: true });
}

export async function POST(request: NextRequest, { params }: { params: Promise<{ id: string }> }) {
  const access = await admin(request);
  if (!access) return NextResponse.json({ error: "Unauthorized" }, { status: 403 });
  const { id } = await params;
  const form = await request.formData();
  const previousPath = String(form.get("previousPath") ?? "");
  const file = form.get("file");
  if (!previousPath || !(file instanceof File)) return NextResponse.json({ error: "Choose a replacement document." }, { status: 400 });
  if (file.size === 0 || file.size > 10 * 1024 * 1024) return NextResponse.json({ error: "The replacement document must be smaller than 10 MB." }, { status: 400 });
  const allowed = ["application/pdf", "image/jpeg", "image/png"];
  if (!allowed.includes(file.type)) return NextResponse.json({ error: "Upload a PDF, JPG, or PNG document." }, { status: 400 });
  const { data: doctor, error: doctorError } = await access.client.from("users").select("doctor_documents,role").eq("uid", id).maybeSingle();
  if (doctorError || !doctor || doctor.role !== "doctor") return NextResponse.json({ error: "Doctor profile was not found." }, { status: 404 });
  const documents = Array.isArray(doctor.doctor_documents) ? doctor.doctor_documents.map(String) : [];
  const position = documents.indexOf(previousPath);
  if (position < 0) return NextResponse.json({ error: "The original document was not found on this profile." }, { status: 404 });
  const extension = file.type === "application/pdf" ? "pdf" : file.type === "image/png" ? "png" : "jpg";
  const nextPath = `${id}/${Date.now()}-replacement.${extension}`;
  const { error: uploadError } = await access.client.storage.from("doctor-documents").upload(nextPath, await file.arrayBuffer(), { contentType: file.type, upsert: false });
  if (uploadError) return NextResponse.json({ error: uploadError.message }, { status: 500 });
  documents[position] = nextPath;
  const { error: updateError } = await access.client.from("users").update({ doctor_documents: documents, is_doctor_verified: false, updated_at: new Date().toISOString() }).eq("uid", id);
  if (updateError) { await access.client.storage.from("doctor-documents").remove([nextPath]); return NextResponse.json({ error: updateError.message }, { status: 500 }); }
  await access.client.storage.from("doctor-documents").remove([previousPath]);
  await access.client.from("admin_doctor_audit_log").insert({ doctor_id: id, admin_email: access.email, action: "document_replaced", detail: { previousPath, nextPath } });
  return NextResponse.json({ ok: true, path: nextPath });
}

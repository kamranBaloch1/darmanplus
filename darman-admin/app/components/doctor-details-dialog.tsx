"use client";

import { useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { ArrowLeft, BadgeCheck, CalendarDays, Check, CircleCheck, CircleDollarSign, Clock3, Download, ExternalLink, FileText, Mail, Phone, PlayCircle, ShieldCheck, Star, Stethoscope, Trash2, TrendingUp, UserRound, WalletCards } from "lucide-react";
import StorageImage from "./storage-image";

type Detail = {
  doctor: Record<string, unknown> & { uid: string; name: string; profile_image: string | null; is_doctor_verified: boolean; is_available: boolean; doctor_documents: string[]; documents: { path: string; url: string }[] };
  bookings: Booking[];
  ratings: Rating[];
  transactions: Transaction[];
};
type Person = { name?: string; profile_image?: string | null; phone?: string | null } | null;
type Booking = { id: string; patient_id: string; status: string; consultation_fee: number | null; gross_fee: number | null; commission_amount: number | null; doctor_earning: number | null; created_at: string; completed_at: string | null; follow_up_date: string | null; follow_up_ended_at: string | null; patient: Person };
type Rating = { id: string; patient_id: string; rating: number; review: string | null; created_at: string; patient: Person };
type Transaction = { id: string; transaction_type: string; amount: number; balance_after: number | null; description: string; created_at: string };

const money = (value: unknown) => `Rs. ${Number(value ?? 0).toLocaleString("en-PK", { maximumFractionDigits: 2 })}`;
const date = (value: unknown) => value ? new Intl.DateTimeFormat("en-PK", { dateStyle: "medium", timeStyle: "short" }).format(new Date(String(value))) : "—";
const label = (value: string) => value.replace(/([A-Z])/g, " $1").replace(/_/g, " ").replace(/^./, (letter) => letter.toUpperCase());

export default function DoctorDetailsDialog({ doctorId, token, onClose, onVerified, onUnverified, onDeleted }: { doctorId: string; token: string; onClose: () => void; onVerified: (id: string) => Promise<void>; onUnverified: (id: string) => Promise<void>; onDeleted?: () => Promise<void> }) {
  const router = useRouter();
  useEffect(() => { if (!window.location.pathname.startsWith("/doctors/")) router.push(`/doctors/${doctorId}`); }, [doctorId, router]);
  const [data, setData] = useState<Detail | null>(null);
  const [error, setError] = useState("");
  const [verifying, setVerifying] = useState(false);
  const [confirmUnverify, setConfirmUnverify] = useState(false);
  const [confirmDelete, setConfirmDelete] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const load = async () => {
    try {
      setError("");
      const response = await fetch(`/api/admin/doctors/${doctorId}`, { headers: { Authorization: `Bearer ${token}` } });
      const json = await response.json();
      if (!response.ok) throw Error(json.error ?? "Could not load the doctor profile.");
      setData(json);
    } catch (cause) {
      setError(cause instanceof Error ? cause.message : "Could not load the doctor profile.");
    }
  };
  useEffect(() => { void load(); }, [doctorId]);
  const verify = async () => {
    setVerifying(true);
    try { await onVerified(doctorId); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : "Doctor could not be verified."); } finally { setVerifying(false); }
  };
  const unverify = async () => {
    setVerifying(true);
    try { await onUnverified(doctorId); await load(); } catch (cause) { setError(cause instanceof Error ? cause.message : "Doctor could not be unverified."); } finally { setVerifying(false); }
  };
  const deleteDoctor = async () => {
    setDeleting(true);
    setError("");
    try {
      const response = await fetch(`/api/admin/doctors/${doctorId}`, {
        method: "DELETE",
        headers: { Authorization: `Bearer ${token}` },
      });
      const result = await response.json();
      if (!response.ok) throw Error(result.error ?? "Doctor account could not be deleted.");
      setConfirmDelete(false);
      if (typeof onDeleted === "function") {
        await onDeleted();
      } else {
        onClose();
        router.push("/verification");
      }
    } catch (cause) {
      setConfirmDelete(false);
      setError(cause instanceof Error ? cause.message : "Doctor account could not be deleted.");
    } finally {
      setDeleting(false);
    }
  };
  return <main className="doctor-page">
    <article className="doctor-page-inner">
      <button className="detail-back" onClick={onClose}><ArrowLeft />Back to doctors</button>
      {!data && !error && <div className="detail-loading"><span /><p>Loading complete doctor overview…</p></div>}
      {error && <div className="detail-error"><ShieldCheck /><h2>Profile could not be loaded</h2><p>{error}</p><button className="blue" onClick={() => void load()}>Try again</button></div>}
      {data && <Profile data={data} token={token} verify={verify} requestUnverify={() => setConfirmUnverify(true)} requestDelete={() => setConfirmDelete(true)} verifying={verifying} reload={load} />}
      {confirmUnverify && <div className="confirm-overlay"><section className="confirm-dialog"><h2>Unverify this doctor?</h2><p>This removes verified status and immediately sets the doctor offline. They will no longer be available for patient bookings.</p><div><button onClick={() => setConfirmUnverify(false)}>Keep verified</button><button className="danger-action" disabled={verifying} onClick={() => { setConfirmUnverify(false); void unverify(); }}>{verifying ? "Updating…" : "Unverify doctor"}</button></div></section></div>}
      {confirmDelete && <div className="confirm-overlay"><section className="confirm-dialog"><h2>Delete this doctor account?</h2><p>This permanently removes the unverified doctor’s login and profile. Accounts with consultations or wallet funds cannot be deleted.</p><div><button onClick={() => setConfirmDelete(false)}>Cancel</button><button className="danger-action" disabled={deleting} onClick={() => void deleteDoctor()}>{deleting ? "Deleting…" : "Delete permanently"}</button></div></section></div>}
    </article>
  </main>;
}

function Profile({ data, token, verify, requestUnverify, requestDelete, verifying, reload }: { data: Detail; token: string; verify: () => Promise<void>; requestUnverify: () => void; requestDelete: () => void; verifying: boolean; reload: () => Promise<void> }) {
  const doctor = data.doctor;
  const completed = data.bookings.filter((booking) => booking.status === "completed");
  const cancelled = data.bookings.filter((booking) => booking.status === "cancelled");
  const active = data.bookings.filter((booking) => ["pending", "accepted", "inProgress"].includes(booking.status));
  const followUps = data.bookings.filter((booking) => booking.follow_up_date && !booking.follow_up_ended_at);
  const totalEarned = completed.reduce((total, booking) => total + Number(booking.doctor_earning ?? 0), 0);
  const grossRevenue = completed.reduce((total, booking) => total + Number(booking.gross_fee ?? booking.consultation_fee ?? 0), 0);
  const totalCommission = completed.reduce((total, booking) => total + Number(booking.commission_amount ?? 0), 0);
  const completionRate = data.bookings.length ? Math.round((completed.length / data.bookings.length) * 100) : 0;
  const rating = Number(doctor.doctor_rating ?? 0);
  const profileChecks = [doctor.profile_image, doctor.specialization, doctor.title, doctor.qualification, doctor.medical_license_number, doctor.consultation_fee, doctor.bio].filter(Boolean).length;
  const uniquePatients = new Set(data.bookings.map((booking) => booking.patient_id)).size;
  const averageFee = completed.length ? completed.reduce((total, booking) => total + Number(booking.consultation_fee ?? 0), 0) / completed.length : 0;
  const latestConsultation = data.bookings[0];
  const exportHistory = () => { const rows = [["Patient","Status","Consultation fee","Doctor earning","Date","Follow-up"], ...data.bookings.map((booking) => [booking.patient?.name ?? "Patient", booking.status, String(booking.consultation_fee ?? 0), String(booking.doctor_earning ?? 0), booking.completed_at ?? booking.created_at, booking.follow_up_date ?? ""])]; const csv = rows.map((row) => row.map((cell) => `"${cell.replaceAll("\"", "\"\"")}"`).join(",")).join("\n"); const link = document.createElement("a"); link.href = URL.createObjectURL(new Blob([csv], { type: "text/csv" })); link.download = `${String(doctor.name || "doctor").replaceAll(" ", "-").toLowerCase()}-consultations.csv`; link.click(); URL.revokeObjectURL(link.href); };
  return <>
    <header className="detail-hero">
      <div className="detail-avatar">{doctor.profile_image ? <StorageImage src={doctor.profile_image} size={128} /> : <UserRound />}</div>
      <div className="doctor-identity"><p>DOCTOR PROFILE · ADMIN REVIEW</p><h1>{String(doctor.name || "Unnamed doctor")}{doctor.is_doctor_verified && <BadgeCheck />}</h1><span>{String(doctor.title || "Doctor")} <b>•</b> {String(doctor.specialization || "Specialization not provided")}</span><div className="detail-pills"><i className={doctor.is_doctor_verified ? "ok" : "wait"}>{doctor.is_doctor_verified ? <><Check /> Verified clinician</> : "Verification pending"}</i><i className={doctor.is_available ? "online" : "offline"}>{doctor.is_available ? "Available for bookings" : "Currently offline"}</i><i className="fee-pill">Consultation fee · {doctor.consultation_fee ? money(doctor.consultation_fee) : "Not set"}</i>{!doctor.is_profile_completed&&<i className="profile-incomplete-detail">Profile incomplete</i>}</div></div>
      <div className="header-profile-data"><span><small>DOCTOR ID</small><b>{doctor.uid.slice(0, 8).toUpperCase()}</b></span><span><small>MEMBER SINCE</small><b>{doctor.created_at ? new Intl.DateTimeFormat("en-PK", { month: "short", year: "numeric" }).format(new Date(String(doctor.created_at))) : "—"}</b></span>{typeof doctor.intro_video_url === "string" && doctor.intro_video_url && (
  <a href={doctor.intro_video_url} target="_blank" rel="noreferrer">
    <PlayCircle />
    Watch intro video
  </a>
)}</div>
      <div className="detail-actions"><span>Last updated<br /><b>{date(doctor.updated_at)}</b></span>{doctor.is_doctor_verified ? <button className="unverify-detail" disabled={verifying} onClick={requestUnverify}>{verifying ? "Updating…" : "Unverify doctor"}</button> : <><button className="delete-doctor-detail" onClick={requestDelete}><Trash2 />Delete</button><button className="blue verify-detail" disabled={verifying} onClick={() => void verify()}><BadgeCheck />{verifying ? "Verifying…" : "Verify doctor"}</button></>}</div>
    </header>
    <section className="detail-stats">
      <Metric icon={<WalletCards />} label="Wallet balance" value={money(doctor.wallet_balance)} />
      <Metric icon={<Star />} label="Average rating" value={`${rating.toFixed(1)} / 5`} helper={`${data.ratings.length} patient ratings`} />
      <Metric icon={<Stethoscope />} label="Completed consultations" value={String(doctor.doctor_completed_consultation_count ?? completed.length)} helper={`${completionRate}% completion rate`} />
      <Metric icon={<CircleDollarSign />} label="Recorded earnings" value={money(totalEarned)} helper="After platform commission" />
    </section>
    <section className="doctor-command-center">
      <div className="command-title"><p>OPERATIONS AT A GLANCE</p><h2>Doctor activity overview</h2><span>Patient care, consultation value and follow-up workload in one clear view.</span></div>
      <div className="command-metrics"><article><small>PATIENTS SERVED</small><strong>{uniquePatients}</strong><span>unique patients across all bookings</span></article><article><small>AVERAGE CONSULTATION FEE</small><strong>{money(averageFee)}</strong><span>from completed consultations</span></article><article><small>FOLLOW-UPS TO MANAGE</small><strong>{followUps.length}</strong><span>scheduled sessions not yet closed</span></article><article><small>MOST RECENT ACTIVITY</small><strong>{latestConsultation ? label(latestConsultation.status) : "No activity"}</strong><span>{latestConsultation ? date(latestConsultation.completed_at ?? latestConsultation.created_at) : "No consultations yet"}</span></article></div>
    </section>
    <section className="operations-lower">
      <article className="admin-alerts"><div className="section-kicker"><ShieldCheck /> ADMIN ATTENTION</div><h2>Account signals</h2><div className="alert-list">{!doctor.is_doctor_verified && <p className="warning"><i />Verification is still pending. The doctor should not be publicly available.</p>}{data.doctor.documents.length === 0 && <p className="danger"><i />No verification documents have been uploaded.</p>}{rating > 0 && rating < 3.5 && <p className="warning"><i />Rating is below the platform quality threshold.</p>}{cancelled.length >= 3 && <p className="warning"><i />This doctor has {cancelled.length} cancelled consultations to review.</p>}{doctor.is_doctor_verified && data.doctor.documents.length > 0 && rating >= 3.5 && cancelled.length < 3 && <p className="good"><i />No account-quality alerts need attention right now.</p>}</div></article>
      <article className="activity-feed"><div className="section-kicker"><Clock3 /> LATEST ACTIVITY</div><h2>Operational timeline</h2><div>{data.bookings.slice(0, 4).map((booking) => <p key={booking.id}><i className={booking.status} /><span><b>{label(booking.status)} consultation</b><small>{booking.patient?.name || "Patient"} · {date(booking.completed_at ?? booking.created_at)}</small></span></p>)}{!data.bookings.length && <Empty text="No consultation activity yet." />}</div></article>
    </section>
    <section className="insight-grid">
      <article className="performance-card"><div className="section-kicker"><TrendingUp /> PERFORMANCE OVERVIEW</div><h2>Consultation health</h2><div className="performance-body"><div className="progress-ring" style={{ "--progress": `${completionRate * 3.6}deg` } as React.CSSProperties}><strong>{completionRate}%</strong><span>completed</span></div><div className="performance-list"><MetricLine label="Active requests" value={active.length} color="blue" /><MetricLine label="Completed" value={completed.length} color="green" /><MetricLine label="Cancelled" value={cancelled.length} color="red" /><MetricLine label="Open follow-ups" value={followUps.length} color="orange" /></div></div></article>
      <article className="revenue-card"><div className="section-kicker"><CircleDollarSign /> REVENUE OVERVIEW</div><h2>Consultation settlement</h2><div className="revenue-figures"><div><small>Gross consultation value</small><strong>{money(grossRevenue)}</strong></div><div><small>Platform commission</small><strong>{money(totalCommission)}</strong></div><div><small>Doctor earnings</small><strong>{money(totalEarned)}</strong></div></div><div className="revenue-bar"><span style={{ width: grossRevenue ? `${Math.min(100, Math.round((totalEarned / grossRevenue) * 100))}%` : "0%" }} /></div><p><CircleCheck /> {grossRevenue ? `${Math.round((totalEarned / grossRevenue) * 100)}% of recorded consultation value is settled to the doctor.` : "Settlement data will appear after completed consultations."}</p></article>
      <article className="profile-health"><div className="section-kicker"><ShieldCheck /> PROFILE READINESS</div><h2>Verification readiness</h2><div className="health-score"><strong>{profileChecks}<small>/ 7</small></strong><span>profile details supplied</span></div><div className="health-items"><CheckItem yes={Boolean(doctor.profile_image)} text="Profile photo" /><CheckItem yes={Boolean(doctor.medical_license_number)} text="Medical license" /><CheckItem yes={data.doctor.documents.length > 0} text="Verification documents" /><CheckItem yes={Boolean(doctor.intro_video_url)} text="Introduction video" /></div></article>
    </section>
    <div className="detail-grid">
      <section className="detail-section"><h2><UserRound /> Account and identity</h2><Info label="Doctor ID" value={doctor.uid} /><Info label="Email" value={doctor.email} icon={<Mail />} /><Info label="Phone" value={doctor.phone} icon={<Phone />} /><Info label="Email verified" value={doctor.is_email_verified ? "Yes" : "No"} /><Info label="Phone verified" value={doctor.is_phone_verified ? "Yes" : "No"} /><Info label="Gender" value={doctor.gender} /><Info label="Date of birth" value={doctor.date_of_birth} /><Info label="Joined Darman" value={date(doctor.created_at)} /></section>
      <section className="detail-section"><h2><Stethoscope /> Professional information</h2><Info label="Specialization" value={doctor.specialization} /><Info label="Title" value={doctor.title} /><Info label="Qualifications" value={doctor.qualification} /><Info label="Experience" value={doctor.experience_years ? `${doctor.experience_years} years` : null} /><Info label="License number" value={doctor.medical_license_number} /><Info label="Consultation fee" value={doctor.consultation_fee ? money(doctor.consultation_fee) : null} /><Info label="Profile complete" value={doctor.is_profile_completed ? "Yes" : "No"} /><div className="bio"><small>BIO</small><p>{String(doctor.bio || "No bio has been provided.")}</p></div></section>
      <section className="detail-section wallet-section"><h2><WalletCards /> Wallet and settlement</h2><div className="wallet-balance"><small>CURRENT WALLET BALANCE</small><strong>{money(doctor.wallet_balance)}</strong><span>Available for withdrawal or future settlement</span></div><div className="wallet-breakdown"><div><span>Completed consultation value</span><b>{money(grossRevenue)}</b><small>Total paid by patients</small></div><div className="commission"><span>Darman commission</span><b>{money(totalCommission)}</b><small>Platform revenue from this doctor</small></div><div className="earning"><span>Doctor settlement</span><b>{money(totalEarned)}</b><small>Recorded earnings after commission</small></div></div><div className="wallet-status"><span><i />Reserved / pending amount <b>{money(doctor.wallet_reserved_balance)}</b></span><span><i />Recovery due <b>{money(doctor.wallet_recovery_due)}</b></span></div><div className="transaction-list"><h3>Recent wallet activity</h3>{data.transactions.length ? data.transactions.slice(0, 5).map((transaction) => <div key={transaction.id}><span><b>{label(transaction.transaction_type)}</b><small>{transaction.description || date(transaction.created_at)}</small></span><strong>{money(transaction.amount)}</strong></div>) : <Empty text="No wallet transactions yet." />}</div></section>
      <section className="detail-section"><h2><FileText /> Verification documents</h2>{data.doctor.documents.length ? <DocumentList doctorId={doctor.uid} documents={data.doctor.documents} token={token} onReplaced={reload} /> : <Empty text="No verification documents uploaded." />}</section>
    </div>
    <section className="detail-section full-section"><h2><CalendarDays /> Consultation history <small>{data.bookings.length} records</small><button className="export-history" onClick={exportHistory}><Download />Export CSV</button></h2>{data.bookings.length ? <div className="history-table"><div className="history-head"><span>Patient</span><span>Status</span><span>Fee / earnings</span><span>Date</span><span>Follow-up</span></div>{data.bookings.map((booking) => <a className="history-row consultation-link" href={`/consultations/${booking.id}`} key={booking.id}><span className="patient-cell">{booking.patient?.profile_image ? <StorageImage src={booking.patient.profile_image} size={40} /> : <UserRound />}{booking.patient?.name || "Patient record unavailable"}</span><i className={`status ${booking.status}`}>{label(booking.status)}</i><span>{money(booking.consultation_fee)}<small>Earned {money(booking.doctor_earning)}</small></span><span>{date(booking.completed_at ?? booking.created_at)}</span><span>{booking.follow_up_date ? `${booking.follow_up_date}${booking.follow_up_ended_at ? " · ended" : ""}` : "—"}</span></a>)}</div> : <Empty text="This doctor has no consultation history yet." />}</section>
    <section className="detail-section full-section"><h2><Star /> Patient reviews <small>{data.ratings.length} submitted</small></h2>{data.ratings.length ? <div className="reviews">{data.ratings.map((rating) => <article key={rating.id}><div><a className="review-patient-link" href={rating.patient ? `/patients/${rating.patient_id}` : undefined}>{rating.patient?.name || "Patient"}</a><span>{Array.from({ length: 5 }, (_, index) => <Star key={index} className={index < rating.rating ? "filled" : ""} />)}</span></div><p>{rating.review || "No written review."}</p><small>{date(rating.created_at)}</small></article>)}</div> : <Empty text="No patient ratings have been submitted yet." />}</section>
    <DoctorOperations doctorId={doctor.uid} token={token} />
  </>;
}

function DocumentList({ doctorId, documents, token, onReplaced }: { doctorId: string; documents: { path: string; url: string }[]; token: string; onReplaced: () => Promise<void> }) {
  const [busy, setBusy] = useState("");
  const [message, setMessage] = useState("");
  const replace = async (path: string, file?: File) => {
    if (!file) return;
    setBusy(path); setMessage("");
    try {
      const form = new FormData(); form.append("previousPath", path); form.append("file", file);
      const response = await fetch(`/api/admin/doctors/${doctorId}/documents`, { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form });
      const result = await response.json();
      if (!response.ok) throw Error(result.error ?? "Document could not be replaced.");
      setMessage("Document replaced. Doctor verification now requires a fresh review.");
      await onReplaced();
    } catch (cause) { setMessage(cause instanceof Error ? cause.message : "Document could not be replaced."); }
    finally { setBusy(""); }
  };
  return <div className="documents document-manager">{documents.map((document, index) => <div className="document-item" key={document.path}><a href={document.url} target="_blank" rel="noreferrer"><FileText /><span>Document {index + 1}<small>{document.path.split("/").pop()}</small></span><ExternalLink /></a><label className="replace-document"><input type="file" accept="application/pdf,image/jpeg,image/png" disabled={busy === document.path} onChange={event => { void replace(document.path, event.target.files?.[0]); event.currentTarget.value = ""; }} />{busy === document.path ? "Replacing…" : "Replace document"}</label></div>)}{message && <p className="document-message">{message}</p>}</div>;
}

function Metric({ icon, label, value, helper }: { icon: React.ReactNode; label: string; value: string; helper?: string }) { return <article><i>{icon}</i><span><small>{label}</small><strong>{value}</strong>{helper && <em>{helper}</em>}</span></article>; }
function MetricLine({ label, value, color }: { label: string; value: number; color: string }) { return <div><i className={color} /><span>{label}</span><b>{value}</b></div>; }
function CheckItem({ yes, text }: { yes: boolean; text: string }) { return <div className={yes ? "ready" : "missing"}><i>{yes ? <Check /> : <Clock3 />}</i>{text}</div>; }
function Info({ label, value, icon }: { label: string; value: unknown; icon?: React.ReactNode }) { return <div className="info"><small>{label}</small><span>{icon}{value ? String(value) : "—"}</span></div>; }
function Empty({ text }: { text: string }) { return <p className="detail-empty">{text}</p>; }

function DoctorOperations({ doctorId, token }: { doctorId: string; token: string }) {
  const [note, setNote] = useState("");
  const [message, setMessage] = useState("");
  const headers = { "Content-Type": "application/json", Authorization: `Bearer ${token}` };
  const act = async (action: string, value?: boolean) => { const response = await fetch(`/api/admin/doctors/${doctorId}/controls`, { method: "PATCH", headers, body: JSON.stringify({ action, value }) }); const json = await response.json(); setMessage(response.ok ? "Account control updated." : json.error ?? "Could not update account."); };
  const saveNote = async () => { if (!note.trim()) return; const response = await fetch(`/api/admin/doctors/${doctorId}/notes`, { method: "POST", headers, body: JSON.stringify({ body: note }) }); const json = await response.json(); if (response.ok) { setNote(""); setMessage("Internal note saved."); } else setMessage(json.error ?? "Could not save note."); };
  return <section className="detail-section full-section admin-operations"><h2><ShieldCheck /> Admin operations</h2>{message && <p className="operation-message">{message}</p>}<div className="admin-operation-grid"><article><h3>Account controls</h3><p>Manage the doctor’s public availability and account access.</p><div><button onClick={() => void act("offline")}>Force offline</button><button onClick={() => void act("hide", true)}>Hide from catalogue</button><button className="danger-action" onClick={() => void act("suspend", true)}>Suspend account</button></div></article><article><h3>Internal admin note</h3><p>Visible only to authorised Darman staff.</p><textarea value={note} onChange={event => setNote(event.target.value)} placeholder="Add a private note about this doctor…" maxLength={2000} /><button className="blue" onClick={() => void saveNote()}>Save note</button></article><article><h3>Review workflow</h3><p>Documents, audit history, and login/device history use the staff-review data tables after the migration is applied.</p><div className="operation-links"><span>Document approvals and rejections</span><span>Account action audit trail</span><span>Login/device history: no mobile telemetry recorded yet</span></div></article></div></section>;
}

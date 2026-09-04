"use client";

import { useEffect, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { ArrowLeft, CalendarDays, Clock3, MessageCircle, ReceiptText, Star, UserRound, Video, WalletCards } from "lucide-react";
import { createClient } from "@supabase/supabase-js";

const sb = process.env.NEXT_PUBLIC_SUPABASE_URL && process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY ? createClient(process.env.NEXT_PUBLIC_SUPABASE_URL, process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY) : null;
const cash = (n: any) => `Rs. ${Number(n ?? 0).toLocaleString("en-PK")}`;
const date = (v: any) => v ? new Date(v).toLocaleString() : "—";
const label = (v: any) => String(v ?? "—").replaceAll("_", " ");

export default function ConsultationPage() {
  const { id } = useParams<{ id: string }>();
  const router = useRouter();
  const [data, setData] = useState<any>();
  const [error, setError] = useState("");
  useEffect(() => { void load(); }, [id]);
  async function load() {
    try {
      const session = await sb?.auth.getSession();
      const response = await fetch(`/api/admin/consultations/${id}`, { headers: { Authorization: `Bearer ${session?.data.session?.access_token ?? ""}` } });
      const result = await response.json();
      if (!response.ok || !result.booking) throw Error(result.error ?? "Consultation could not be loaded.");
      setData(result);
    } catch (e) { setError(e instanceof Error ? e.message : "Could not load consultation"); }
  }
  if (error) return <Frame><section className="detail-section"><h2>Consultation unavailable</h2><p>{error}</p><button className="blue" onClick={() => void load()}>Try again</button></section></Frame>;
  if (!data) return <Frame>Loading consultation details…</Frame>;
  const b = data.booking, transactions = data.transactions ?? [], messages = data.messages ?? [];
  const gross = b.gross_fee ?? b.consultation_fee ?? 0, commission = b.commission_amount ?? 0, earning = b.doctor_earning ?? Math.max(0, gross - commission);
  const followOpen = b.follow_up_date && !b.follow_up_ended_at;
  const isCancelled = ["cancelled", "canceled"].includes(b.status);
  const cancelledBy = b.cancelled_by === b.doctor_id ? data.doctor?.name || "Doctor" : b.cancelled_by === b.patient_id ? data.patient?.name || "Patient" : b.cancelled_by || "Not recorded";
  return <main className="doctor-page consultation-page"><article className="doctor-page-inner">
    <button className="detail-back" onClick={() => router.back()}><ArrowLeft />Back to consultation history</button>
    <header className="detail-hero consultation-hero"><div className="detail-avatar"><Video /></div><div className="doctor-identity"><p>CONSULTATION OPERATIONS RECORD</p><h1>{data.doctor?.name || "Doctor"} <span>↔</span> {data.patient?.name || "Patient"}</h1><span>{label(b.status)} consultation · Created {date(b.created_at)}</span><div className="detail-pills"><i className={`status ${b.status}`}>{label(b.status)}</i>{followOpen && <i className="fee-pill">Follow-up open · {b.follow_up_date}</i>}<i className="neutral">Booking · {b.id.slice(0, 8)}</i></div></div></header>
    <section className="detail-stats"><Metric icon={<ReceiptText />} label="Consultation fee" value={cash(b.consultation_fee)} /><Metric icon={<WalletCards />} label="Darman commission" value={cash(commission)} /><Metric icon={<WalletCards />} label="Doctor earning" value={cash(earning)} /><Metric icon={<MessageCircle />} label="Chat messages" value={String(messages.length)} /></section>
    <section className="doctor-command-center"><div className="command-title"><p>CONSULTATION SUMMARY</p><h2>Care and settlement overview</h2><span>Review patient care, call progress, payment settlement and follow-up status.</span></div><div className="command-metrics"><article><small>FOLLOW-UP STATUS</small><strong>{b.follow_up_date ? (followOpen ? "Open" : "Completed") : "Not scheduled"}</strong><span>{b.follow_up_date || "No follow-up date"}</span></article><article><small>CHAT ROOM</small><strong>{data.chatRoom?.is_active === false ? "Closed" : "Active"}</strong><span>{data.chatRoom?.id ? `${messages.length} messages recorded` : "No chat room"}</span></article><article><small>CALL STATE</small><strong>{b.call_ended_at ? "Ended" : b.call_started_at ? "Started" : "Not started"}</strong><span>{b.call_started_at ? date(b.call_started_at) : "No call timestamp"}</span></article><article><small>PATIENT RATING</small><strong>{data.rating ? `${data.rating.rating} / 5` : "Not rated"}</strong><span>{data.rating?.review || "No review submitted"}</span></article></div></section>
    <div className="detail-grid">
      <section className="detail-section"><h2><UserRound /> Participants</h2><a className="view-profile" href={`/doctors/${b.doctor_id}`}>Doctor · {data.doctor?.name || "Open doctor profile"}</a><Info label="Doctor phone" value={data.doctor?.phone} /><a className="view-profile" href={`/patients/${b.patient_id}`}>Patient · {data.patient?.name || "Open patient profile"}</a><Info label="Patient phone" value={data.patient?.phone} /><Info label="Chat room ID" value={data.chatRoom?.id} /></section>
      <section className="detail-section"><h2><Clock3 /> Consultation timeline</h2><Info label="Booking created" value={date(b.created_at)} /><Info label="Doctor accepted" value={date(b.accepted_at)} /><Info label="Session requested" value={date(b.session_start_requested_at)} /><Info label="Consultation started" value={date(b.started_at ?? b.call_started_at)} /><Info label="Doctor joined call" value={date(b.doctor_joined_at)} /><Info label="Patient joined call" value={date(b.patient_joined_at)} /><Info label="Call ended" value={date(b.completed_at ?? b.call_ended_at)} /><Info label="Cancelled" value={date(b.cancelled_at)} /></section>
      {isCancelled && <section className="detail-section cancellation-record"><h2>Cancellation record</h2><div className="cancellation-banner"><i className="status cancelled">Cancelled</i><strong>Cancelled by {cancelledBy}</strong><span>{date(b.cancelled_at)}</span></div><Info label="Cancelled by" value={cancelledBy} /><Info label="Cancellation time" value={date(b.cancelled_at)} /><Info label="Reason" value={b.cancellation_reason} /></section>}
      <section className="detail-section"><h2><CalendarDays /> Follow-up care</h2><Info label="Follow-up date" value={b.follow_up_date} /><Info label="Scheduled at" value={date(b.follow_up_scheduled_at)} /><Info label="Patient viewed" value={date(b.follow_up_patient_seen_at)} /><Info label="Follow-up ended" value={date(b.follow_up_ended_at)} /></section>
      <section className="detail-section"><h2><WalletCards /> Settlement detail</h2><div className="wallet-balance"><small>GROSS CONSULTATION VALUE</small><strong>{cash(gross)}</strong><span>Paid by the patient for this consultation</span></div><Info label="Darman commission" value={cash(commission)} /><Info label="Doctor settlement" value={cash(earning)} /><Info label="Transaction records" value={String(transactions.length)} /></section>
    </div>
    <section className="detail-section full-section"><h2><MessageCircle /> Chat history <small>{messages.length} messages</small></h2>{messages.length ? messages.map((m: any) => <div className="history-row" key={m.id}><span>{m.sender_id === b.doctor_id ? data.doctor?.name : data.patient?.name}</span><span>{m.is_deleted ? "This message was deleted" : m.text || m.media_url || m.file_name || (m.type === "voice" ? `Voice message · ${m.voice_duration_seconds ?? 0}s` : label(m.type))}</span><span>{date(m.created_at)}</span></div>) : <p className="detail-empty">No messages recorded for this consultation.</p>}</section>
    <section className="detail-section full-section"><h2><WalletCards /> Settlement transaction history <small>{transactions.length} records</small></h2>{transactions.length ? transactions.map((t: any) => <a className="history-row consultation-link" href={`/wallet-transactions/${t.id}`} key={t.id}><span>{label(t.transaction_type)}</span><span>{cash(t.amount)}</span><span>{t.description || "Settlement transaction"}</span><span>{date(t.created_at)}</span></a>) : <p className="detail-empty">No settlement transactions found.</p>}</section>
    <section className="detail-section full-section"><h2><Star /> Patient rating and review</h2>{data.rating ? <div className="review-detail"><strong>{data.rating.rating} / 5</strong><p>{data.rating.review || "The patient submitted a rating without a written review."}</p><small>{date(data.rating.created_at)}</small></div> : <p className="detail-empty">The patient has not submitted a rating yet.</p>}</section>
  </article></main>;
}

function Frame({ children }: { children: React.ReactNode }) { const router = useRouter(); return <main className="doctor-page"><article className="doctor-page-inner"><button className="detail-back" onClick={() => router.back()}><ArrowLeft />Back to history</button>{children}</article></main>; }
function Metric({ icon, label, value }: { icon: React.ReactNode; label: string; value: string }) { return <article><i>{icon}</i><span><small>{label}</small><strong>{value}</strong></span></article>; }
function Info({ label, value }: { label: string; value: any }) { return <div className="info"><small>{label}</small><span>{value || "—"}</span></div>; }

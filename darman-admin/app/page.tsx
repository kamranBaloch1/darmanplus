"use client";

import { useEffect, useRef, useState } from "react";
import { usePathname, useRouter } from "next/navigation";
import {
  Activity,
  AlertTriangle,
  ArrowRight,
  BadgeCheck,
  BarChart3,
  Banknote,
  CalendarClock,
  CheckCircle2,
  ClipboardList,
  Eye,
  EyeOff,
  LayoutDashboard,
  LogOut,
  ReceiptText,
  Search,
  ShieldCheck,
  Star,
  Stethoscope,
  Users,
  WalletCards,
  XCircle,
} from "lucide-react";
import { createClient, Session } from "@supabase/supabase-js";
import DoctorDetailsDialog from "./components/doctor-details-dialog";

type U = {
  uid: string;
  name: string;
  email?: string;
  phone?: string;
  profile_image?: string;
  specialization?: string;
  is_doctor_verified?: boolean;
  is_profile_completed?: boolean;
};
type C = {
  id: string;
  status: string;
  consultation_fee: number;
  created_at: string;
  completed_at?: string;
  follow_up_date?: string;
  doctor: U | null;
  patient: U | null;
};
type D = {
  doctors: U[];
  patients: U[];
  consultations: C[];
  stats: Record<string, number>;
};
type TopUp = {
  id: string;
  user_id: string;
  amount: number | null;
  currency: string;
  receipt_url: string;
  receipt_signed_url: string;
  status: string;
  response_message?: string;
  created_at: string;
  completed_at?: string;
  user: {
    uid: string;
    name: string;
    email?: string;
    phone?: string;
    profile_image?: string;
    wallet_balance?: number;
  } | null;
};
type FinanceData = {
  summary: {
    topUps: number;
    topUpCount: number;
    revenue: number;
    grossConsultations: number;
    consultationCount: number;
    doctorEarnings: number;
    effectiveCommissionRate: number;
    doctorPayable: number;
    patientFunds: number;
    patientAvailable: number;
    patientReserved: number;
    patientFundHolders: number;
    reservedPatientCount: number;
    totalLiabilities: number;
  };
  doctors: { id: string; name: string; email?: string; profileImage?: string; unpaid: number }[];
  patientFunds: {
    id: string;
    name: string;
    email?: string;
    profileImage?: string;
    available: number;
    reserved: number;
    total: number;
  }[];
  recentTopUps: {
    id: string;
    amount: number;
    description: string;
    created_at: string;
  }[];
  recentActivity: {
    id: string;
    transaction_type: string;
    amount: number;
    description: string;
    created_at: string;
    userName?: string;
  }[];
};
type T =
  | "overview"
  | "finance"
  | "doctors"
  | "patients"
  | "verification"
  | "manual-topups"
  | "wallets"
  | "followups"
  | "reviews"
  | "reports"
  | "consultations";
const sb =
  process.env.NEXT_PUBLIC_SUPABASE_URL &&
  process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
    ? createClient(
        process.env.NEXT_PUBLIC_SUPABASE_URL,
        process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY,
      )
    : null;
const tabs: [T, string, React.ReactNode][] = [
  ["overview", "Overview", <LayoutDashboard />],
  ["finance", "Finance", <Banknote />],
  ["doctors", "Doctors", <Stethoscope />],
  ["patients", "Patients", <Users />],
  ["verification", "Verification", <BadgeCheck />],
  ["manual-topups", "Manual top-ups", <ReceiptText />],
  ["wallets", "Wallets & settlements", <WalletCards />],
  ["followups", "Follow-ups", <CalendarClock />],
  ["reviews", "Ratings & reviews", <Star />],
  ["reports", "Reports & analytics", <BarChart3 />],
  ["consultations", "Consultation history", <ClipboardList />],
];

export default function Home() {
  const router = useRouter(),
    pathname = usePathname();
  const routeTab = (tabs.find(([id]) => pathname === `/${id}`)?.[0] ??
    "overview") as T;
  const [s, setS] = useState<Session | null>(null),
    [d, setD] = useState<D | null>(null),
    [t, setT] = useState<T>(routeTab),
    [q, setQ] = useState(""),
    [doctorId, setDoctorId] = useState<string | null>(null);
  useEffect(() => {
    setT(routeTab);
    setQ("");
  }, [routeTab]);
  useEffect(() => {
    if (!sb) return;
    const acceptSession = async (session: Session | null) => {
      if (!session) {
        setS(null);
        setD(null);
        return;
      }
      const response = await fetch("/api/admin/users", {
        headers: { Authorization: `Bearer ${session.access_token}` },
      });
      if (!response.ok) {
        setS(null);
        setD(null);
        await sb.auth.signOut();
        return;
      }
      setD(await response.json());
      setS(session);
    };
    void sb.auth.getSession().then((x) => acceptSession(x.data.session));
    const subscription = sb.auth.onAuthStateChange((_, session) => {
      void acceptSession(session);
    }).data.subscription;
    return () => subscription.unsubscribe();
  }, []);
  const load = async () => {
    const r = await fetch("/api/admin/users", {
      headers: { Authorization: `Bearer ${s?.access_token}` },
    });
    if (r.status === 401 || r.status === 403) {
      setD(null);
      await sb?.auth.signOut();
      return;
    }
    setD(await r.json());
  };
  useEffect(() => {
    if (s) void load();
  }, [s]);
  const navigate = (next: T) => {
    setT(next);
    setQ("");
    router.push(`/${next}`);
  };
  if (!sb)
    return (
      <main className="setup">
        <h1>Configure Darman Admin</h1>
      </main>
    );
  if (!s) return <Login />;
  const doctors = d?.doctors ?? [],
    patients = d?.patients ?? [],
    cs = d?.consultations ?? [],
    verified = doctors.filter((x) => x.is_doctor_verified).length,
    pending = doctors.length - verified,
    incomplete = doctors.filter(
      (x) => x.is_doctor_verified && !x.is_profile_completed,
    ).length;
  const title = tabs.find((x) => x[0] === t)?.[1] ?? "Overview";
  const people = (t === "patients"
    ? patients
    : t === "verification"
    ? doctors.filter((x) => !x.is_doctor_verified)
    : doctors.filter((x) => x.is_doctor_verified)
  ).filter((x) =>
    `${x.name} ${x.email ?? ""}`.toLowerCase().includes(q.toLowerCase()),
  );
  return (
    <main className="shell">
      <aside>
        <div className="brand">
          <b>
            <Activity />
          </b>
          Darman<span>Admin</span>
        </div>
        <small>PLATFORM OPERATIONS</small>
        {tabs.map(([id, tabLabel, icon]) => (
          <button
            key={id}
            className={t === id ? "nav active" : "nav"}
            onClick={() => navigate(id)}
          >
            {icon}
            {tabLabel}
          </button>
        ))}
        <button
          className="sidebar-signout"
          onClick={() => void sb.auth.signOut()}
          title="Sign out"
        >
          <LogOut />
          <span>Sign out</span>
        </button>
      </aside>
      <section className="content">
        <header>
          <div>
            <p>DARMAN PLATFORM</p>
            <h1>{title}</h1>
          </div>
          <span className="secure">
            <ShieldCheck />
            Secure admin workspace
          </span>
        </header>
        {t === "overview" ? (
          <Overview
            doctors={doctors}
            patients={patients}
            consultations={cs}
            verified={verified}
            pending={pending}
            incomplete={incomplete}
            go={navigate}
          />
        ) : t === "manual-topups" ? (
          <ManualTopUps token={s.access_token} />
        ) : t === "finance" ? (
          <Finance token={s.access_token} />
        ) : (
          <section className="panel">
            <div className="tools">
              <label>
                <Search />
                <input
                  value={q}
                  onChange={(e) => setQ(e.target.value)}
                  placeholder="Search records…"
                />
              </label>
              {t === "doctors" && (
                <div className="list-counts">
                  <span className="count-total">
                    {doctors.length} Total doctors
                  </span>
                  <span className="count-verified">{verified} Verified</span>
                  <span className="count-pending">{pending} Pending</span>
                  <span className="count-incomplete">
                    {incomplete} Verified doctors with incomplete profiles
                  </span>
                </div>
              )}
              {t === "patients" && (
                <div className="list-counts">
                  <span className="count-total">
                    {patients.length} Total patients
                  </span>
                </div>
              )}
            </div>
            {t === "consultations" || t === "followups" ? (
              <History
                rows={
                  t === "followups" ? cs.filter((x) => x.follow_up_date) : cs
                }
              />
            ) : (
              <div className="cards">
                {people.map((x) => (
                  <article className="card" key={x.uid}>
                    {t !== "patients" && (
                      <div className="doctor-card-statuses">
                        <i
                          className={
                            x.is_doctor_verified
                              ? "verified doctor-status"
                              : "pending doctor-status"
                          }
                        >
                          {x.is_doctor_verified ? "Verified" : "Pending review"}
                        </i>
                        {x.is_doctor_verified && !x.is_profile_completed && (
                          <i className="profile-incomplete-card">
                            Profile incomplete
                          </i>
                        )}
                      </div>
                    )}
                    <div className="doctor-card-user">
                      {x.profile_image ? (
                        <img src={x.profile_image} alt="" />
                      ) : (
                        <b>{(x.name || "U")[0]}</b>
                      )}
                      <span>
                        <h3>{x.name}</h3>
                        <p>
                          {x.specialization ||
                            x.phone ||
                            x.email ||
                            "No details"}
                        </p>
                      </span>
                    </div>
                    {t === "patients" ? (
                      <a className="view-profile" href={`/patients/${x.uid}`}>
                        Open patient profile
                      </a>
                    ) : (
                      <button
                        className="view-profile"
                        onClick={() => setDoctorId(x.uid)}
                      >
                        Open full profile
                      </button>
                    )}
                  </article>
                ))}
              </div>
            )}
          </section>
        )}
      </section>
      {doctorId && (
        <DoctorDetailsDialog
          doctorId={doctorId}
          token={s.access_token}
          onClose={() => setDoctorId(null)}
          onVerified={async (id) => {
            await fetch(`/api/admin/doctors/${id}/verify`, {
              method: "PATCH",
              headers: { Authorization: `Bearer ${s.access_token}` },
            });
            void load();
          }}
          onUnverified={async (id) => {
            await fetch(`/api/admin/doctors/${id}/verify`, {
              method: "DELETE",
              headers: { Authorization: `Bearer ${s.access_token}` },
            });
            void load();
          }}
        />
      )}
    </main>
  );
}

function Finance({ token }: { token: string }) {
  const [data, setData] = useState<FinanceData | null>(null),
    [loading, setLoading] = useState(true),
    [error, setError] = useState(""),
    [range, setRange] = useState<"all" | "today" | "week" | "month" | "custom">("all"),
    [from, setFrom] = useState(""),
    [to, setTo] = useState("");

  useEffect(() => {
    const now = new Date();
    let start = "";
    let end = "";
    if (range === "today") {
      start = new Date(now.getFullYear(), now.getMonth(), now.getDate()).toISOString();
    } else if (range === "week") {
      start = new Date(now.getTime() - 7 * 86400000).toISOString();
    } else if (range === "month") {
      start = new Date(now.getFullYear(), now.getMonth(), 1).toISOString();
    } else if (range === "custom") {
      if (from) start = new Date(`${from}T00:00:00`).toISOString();
      if (to) end = new Date(`${to}T23:59:59`).toISOString();
    }
    const params = new URLSearchParams();
    if (start) params.set("from", start);
    if (end) params.set("to", end);
    setLoading(true);
    setError("");
    fetch(`/api/admin/finance?${params}`, {
      headers: { Authorization: `Bearer ${token}` },
    })
      .then(async (response) => {
        const result = await response.json();
        if (!response.ok) throw new Error(result.error ?? "Finance data could not be loaded.");
        setData(result);
      })
      .catch((reason) => setError(reason.message))
      .finally(() => setLoading(false));
  }, [token, range, from, to]);

  const money = (value: number) => `Rs. ${Number(value ?? 0).toLocaleString("en-PK")}`;
  if (loading && !data) return <p className="detail-empty">Loading finance overview...</p>;
  if (error && !data) return <p className="detail-empty">{error}</p>;
  const summary = data?.summary;

  return (
    <section className="finance-page">
      <div className="finance-heading">
        <div>
          <p>FINANCIAL CONTROL</p>
          <h2>Money position and movement</h2>
          <span>Monitor income and funds currently owed to patients and doctors.</span>
        </div>
        <div className="finance-toolbar"><div className="topup-tabs">
          {(["all", "today", "week", "month", "custom"] as const).map((option) => (
            <button key={option} className={range === option ? "selected" : ""} onClick={() => setRange(option)}>
              {option === "all" ? "All time" : option}
            </button>
          ))}
        </div></div>
      </div>
      {range === "custom" && <div className="finance-custom-row"><span>Transaction period</span><div className="finance-dates"><input type="date" value={from} onChange={(event) => setFrom(event.target.value)} /><span>to</span><input type="date" value={to} onChange={(event) => setTo(event.target.value)} /></div></div>}

      <div className="finance-position">
        <article className="finance-primary"><small>Darman revenue</small><strong>{money(summary?.revenue ?? 0)}</strong><span>Commission earned in selected period</span><em>{(summary?.effectiveCommissionRate ?? 0).toFixed(1)}% effective commission</em></article>
        <article><small>Total funds owed</small><strong>{money(summary?.totalLiabilities ?? 0)}</strong><span>Current patient funds and doctor balances</span></article>
        <div className="finance-liability-split"><span><small>Patient funds held</small><b>{money(summary?.patientFunds ?? 0)}</b><em>{money(summary?.patientAvailable ?? 0)} available · {money(summary?.patientReserved ?? 0)} reserved</em><em>{summary?.patientFundHolders ?? 0} patients</em></span><span><small>Doctor payables</small><b>{money(summary?.doctorPayable ?? 0)}</b></span></div>
      </div>

      <div className="finance-summary">
        <article><small>Patient top-ups</small><strong>{money(summary?.topUps ?? 0)}</strong><span>{summary?.topUpCount ?? 0} successful wallet credits</span></article>
        <article><small>Consultation volume</small><strong>{money(summary?.grossConsultations ?? 0)}</strong><span>{summary?.consultationCount ?? 0} completed settlements</span></article>
        <article><small>Doctor earnings</small><strong>{money(summary?.doctorEarnings ?? 0)}</strong><span>Earnings generated in period</span></article>
        <article><small>Reserved patient funds</small><strong>{money(summary?.patientReserved ?? 0)}</strong><span>{summary?.reservedPatientCount ?? 0} patients · {money(summary?.patientAvailable ?? 0)} available</span></article>
      </div>

      <div className="finance-grid">
        <div className="finance-column">
          <section className="panel finance-panel finance-liabilities-panel">
            <div className="finance-panel-head"><div><small>LIABILITIES</small><h2>Doctor payables</h2></div><b>{data?.doctors.length ?? 0} doctors</b></div>
            <div className="finance-list finance-people-list">
              {data?.doctors.map((doctor) => (
                <a className="finance-person" href={`/doctors/${doctor.id}`} key={doctor.id}>{doctor.profileImage ? <img src={doctor.profileImage} alt="" /> : <i>{(doctor.name || "D")[0]}</i>}<span><strong>{doctor.name || "Unnamed doctor"}</strong><small>View doctor profile</small></span><b>{money(doctor.unpaid)}</b><ArrowRight /></a>
              ))}
              {!data?.doctors.length && <p className="detail-empty">No unpaid doctor balances.</p>}
            </div>
          </section>
          <section className="panel finance-panel finance-patient-panel">
            <div className="finance-panel-head"><div><small>CUSTOMER FUNDS</small><h2>Patient funds held</h2></div><b>{data?.patientFunds.length ?? 0} patients</b></div>
            <div className="finance-list finance-people-list">
              {data?.patientFunds.map((patient) => (
                <a className="finance-person patient-fund-person" href={`/patients/${patient.id}`} key={patient.id}>{patient.profileImage ? <img src={patient.profileImage} alt="" /> : <i>{(patient.name || "P")[0]}</i>}<span><strong>{patient.name || "Unnamed patient"}</strong><small>{money(patient.available)} available · {money(patient.reserved)} reserved</small></span><b>{money(patient.total)}</b><ArrowRight /></a>
              ))}
              {!data?.patientFunds.length && <p className="detail-empty">No patient funds are currently held.</p>}
            </div>
          </section>
        </div>
        <section className="panel finance-panel finance-ledger-panel">
          <div className="finance-panel-head"><div><small>LEDGER</small><h2>Recent money movement</h2></div><b>{data?.recentActivity.length ?? 0} entries</b></div>
          <div className="finance-list">
            {data?.recentActivity.map((entry) => (
              <article key={entry.id}><i className={`finance-kind ${entry.transaction_type}`}>{entry.transaction_type.replaceAll("_", " ")}</i><span><strong>{entry.userName || entry.description}</strong><small>{new Date(entry.created_at).toLocaleString()}</small></span><b className={entry.amount >= 0 ? "finance-positive" : "finance-negative"}>{entry.amount >= 0 ? "+" : "-"}{money(Math.abs(entry.amount))}</b></article>
            ))}
            {!data?.recentActivity.length && <p className="detail-empty">No financial activity in this period.</p>}
          </div>
        </section>
      </div>
      <p className="finance-note">Top-ups are customer funds, not Darman revenue. Current patient and doctor balances are shown regardless of the selected transaction period.</p>
    </section>
  );
}

function Login() {
  const [email, setEmail] = useState(""),
    [password, setPassword] = useState(""),
    [showPassword, setShowPassword] = useState(false),
    [error, setError] = useState(""),
    [loading, setLoading] = useState(false);
  async function submit(e: React.FormEvent) {
    e.preventDefault();
    setError("");
    setLoading(true);
    const { data, error } = await sb!.auth.signInWithPassword({
      email: email.trim(),
      password,
    });
    if (error || !data.session) {
      setLoading(false);
      setError("Incorrect email or password.");
      return;
    }
    const authorization = await fetch("/api/admin/users", {
      headers: { Authorization: `Bearer ${data.session.access_token}` },
    });
    if (!authorization.ok) {
      await sb!.auth.signOut();
      setLoading(false);
      setError("This email is not authorized for Darman Admin.");
      return;
    }
    setLoading(false);
  }
  return (
    <main className="login">
      <section>
        <div className="brand">
          <b>
            <Activity />
          </b>
          Darman<span>Admin</span>
        </div>
        <div className="copy">
          <p>SECURE ADMIN ACCESS</p>
          <h1>Sign in to Darman Admin</h1>
        </div>
        <form onSubmit={submit}>
          <label>
            Email
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="admin@example.com"
              required
            />
          </label>
          <label>
            Password
            <span className="password-field">
              <input
                type={showPassword ? "text" : "password"}
                value={password}
                onChange={(e) => setPassword(e.target.value)}
                placeholder="Password"
                required
              />
              <button
                type="button"
                onClick={() => setShowPassword((visible) => !visible)}
                aria-label={showPassword ? "Hide password" : "Show password"}
                title={showPassword ? "Hide password" : "Show password"}
              >
                {showPassword ? <EyeOff /> : <Eye />}
              </button>
            </span>
          </label>
          {error && <em>{error}</em>}
          <button disabled={loading}>
            {loading ? "Signing in..." : "Sign in"}
          </button>
        </form>
      </section>
    </main>
  );
}

function ManualTopUps({ token }: { token: string }) {
  const [rows, setRows] = useState<TopUp[]>([]),
    [loading, setLoading] = useState(true),
    [busy, setBusy] = useState(""),
    [message, setMessage] = useState(""),
    [filter, setFilter] = useState<"pending" | "approved" | "rejected" | "all">(
      "pending",
    ),
    [search, setSearch] = useState(""),
    [from, setFrom] = useState(""),
    [to, setTo] = useState(""),
    [draft, setDraft] = useState({ amount: "", reason: "" }),
    [dialog, setDialog] = useState<{
      action: "approve" | "reject";
      row: TopUp;
    } | null>(null),
    [alerts, setAlerts] = useState(false);
  const known = useRef<Set<string>>(new Set()),
    ready = useRef(false);
  const load = async (silent = false) => {
    if (!silent) setLoading(true);
    const r = await fetch("/api/admin/manual-topups", {
        headers: { Authorization: `Bearer ${token}` },
      }),
      j = await r.json(),
      next: TopUp[] = j.requests ?? [];
    const fresh = next.filter(
      (x) =>
        ["pending", "submitted"].includes(x.status) && !known.current.has(x.id),
    );
    next.forEach((x) => known.current.add(x.id));
    if (
      ready.current &&
      fresh.length &&
      alerts &&
      typeof window !== "undefined" &&
      Notification.permission === "granted"
    ) {
      const x = fresh[0];
      new Notification("New manual payment request", {
        body: `${
          x.user?.name || "A patient"
        } uploaded a wallet top-up receipt.`,
      });
    }
    ready.current = true;
    setRows(next);
    if (!silent) setLoading(false);
  };
  useEffect(() => {
    void load();
    const timer = setInterval(() => void load(true), 20000);
    return () => clearInterval(timer);
  }, [token, alerts]);
  async function enableAlerts() {
    if (typeof window === "undefined" || !("Notification" in window)) {
      setMessage("Browser notifications are not supported here.");
      return;
    }
    const permission = await Notification.requestPermission();
    setAlerts(permission === "granted");
    setMessage(
      permission === "granted"
        ? "Admin alerts enabled for new payment requests."
        : "Notification permission was not allowed.",
    );
  }
  async function decide() {
    if (!dialog) return;
    setBusy(dialog.row.id);
    setMessage("");
    const r = await fetch(`/api/admin/manual-topups/${dialog.row.id}`, {
        method: "PATCH",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${token}`,
        },
        body: JSON.stringify({
          action: dialog.action,
          amount: draft.amount,
          reason: draft.reason,
        }),
      }),
      j = await r.json();
    setBusy("");
    if (!r.ok) {
      setMessage(j.error ?? "Could not update request.");
      return;
    }
    setMessage(
      dialog.action === "approve"
        ? "Wallet top-up approved and patient notified."
        : "Request rejected and patient notified.",
    );
    setDialog(null);
    setDraft({ amount: "", reason: "" });
    void load();
  }
  const pending = rows.filter((x) =>
      ["pending", "submitted"].includes(x.status),
    ).length,
    done = rows.length - pending,
    cash = (n: number | null | undefined) =>
      n == null ? "Amount pending" : `Rs. ${Number(n).toLocaleString("en-PK")}`;
  const visible = rows
    .filter((x) =>
      filter === "all" || filter === "pending"
        ? ["pending", "submitted"].includes(x.status)
        : filter === "approved"
        ? x.status === "succeeded"
        : x.status === "failed",
    )
    .filter((x) =>
      `${x.user?.name ?? ""} ${x.user?.phone ?? ""} ${x.user?.email ?? ""} ${
        x.user_id
      }`
        .toLowerCase()
        .includes(search.toLowerCase()),
    )
    .filter(
      (x) => !from || new Date(x.created_at) >= new Date(`${from}T00:00:00`),
    )
    .filter((x) => !to || new Date(x.created_at) <= new Date(`${to}T23:59:59`))
    .sort(
      (a, b) =>
        new Date(b.completed_at ?? b.created_at).getTime() -
        new Date(a.completed_at ?? a.created_at).getTime(),
    );
  return (
    <section className="manual-topups">
      <div className="topup-summary">
        <article>
          <small>Pending review</small>
          <strong>{pending}</strong>
        </article>
        <article>
          <small>Approved payments</small>
          <strong>{rows.filter((x) => x.status === "succeeded").length}</strong>
        </article>
        <article>
          <small>Rejected receipts</small>
          <strong>{rows.filter((x) => x.status === "failed").length}</strong>
        </article>
        <article>
          <small>Total credited</small>
          <strong>
            {cash(
              rows
                .filter((x) => x.status === "succeeded")
                .reduce((n, x) => n + Number(x.amount ?? 0), 0),
            )}
          </strong>
        </article>
      </div>
      <section className="panel">
        <div className="topup-toolbar">
          <div className="topup-tabs">
            {(["pending", "approved", "rejected", "all"] as const).map((x) => (
              <button
                key={x}
                className={filter === x ? "selected" : ""}
                onClick={() => setFilter(x)}
              >
                {x}
              </button>
            ))}
          </div>
          <label>
            <Search />
            <input
              value={search}
              onChange={(e) => setSearch(e.target.value)}
              placeholder="Search patient, phone or email"
            />
          </label>
          <input
            type="date"
            value={from}
            onChange={(e) => setFrom(e.target.value)}
          />
          <input
            type="date"
            value={to}
            onChange={(e) => setTo(e.target.value)}
          />
          <button
            className={alerts ? "alert-enabled" : "alert-enable"}
            onClick={() => void enableAlerts()}
          >
            {alerts ? "Alerts on" : "Enable alerts"}
          </button>
        </div>
        {message && <div className="topup-message">{message}</div>}
        {loading ? (
          <p className="detail-empty">Loading manual top-up requests...</p>
        ) : (
          <div className="topup-list">
            {visible.map((x) => (
              <article className="topup-row" key={x.id}>
                <div className="topup-user">
                  {x.user?.profile_image ? (
                    <img src={x.user.profile_image} alt="" />
                  ) : (
                    <b>{(x.user?.name || "U")[0]}</b>
                  )}
                  <span>
                    <strong>{x.user?.name || "Unknown user"}</strong>
                    <small>{x.user?.phone || x.user?.email || x.user_id}</small>
                  </span>
                </div>
                <span>
                  <small>Submitted</small>
                  <b>{new Date(x.created_at).toLocaleString()}</b>
                </span>
                <i className={`status ${x.status}`}>{x.status}</i>
                <span>
                  <small>Amount</small>
                  <b>{cash(x.amount)}</b>
                </span>
                <a
                  className="receipt-link"
                  href={x.receipt_signed_url}
                  target="_blank"
                >
                  <Eye />
                  View receipt
                </a>
                {["pending", "submitted"].includes(x.status) ? (
                  <div className="topup-actions">
                    <button
                      className="blue"
                      disabled={busy === x.id}
                      onClick={() => {
                        setDraft({ amount: "", reason: "" });
                        setDialog({ action: "approve", row: x });
                      }}
                    >
                      <CheckCircle2 />
                      Approve payment
                    </button>
                    <button
                      className="reject-topup"
                      disabled={busy === x.id}
                      onClick={() => {
                        setDraft({ amount: "", reason: "" });
                        setDialog({ action: "reject", row: x });
                      }}
                    >
                      <XCircle />
                      Reject
                    </button>
                  </div>
                ) : (
                  <small className="topup-note">
                    {x.response_message || "Processed"}
                  </small>
                )}
              </article>
            ))}
            {!visible.length && (
              <p className="detail-empty">No manual top-up requests found.</p>
            )}
          </div>
        )}
      </section>
      {dialog && (
        <div className="confirm-overlay">
          <article className="confirm-dialog topup-dialog">
            <h2>
              {dialog.action === "approve"
                ? "Approve manual payment"
                : "Reject manual payment"}
            </h2>
            <p>
              {dialog.row.user?.name || "This patient"} submitted a JazzCash
              receipt. Review it before confirming.
            </p>
            <a
              className="receipt-link dialog-receipt"
              href={dialog.row.receipt_signed_url}
              target="_blank"
            >
              <Eye />
              Open receipt
            </a>
            {dialog.action === "approve" ? (
              <label>
                Credited amount
                <input
                  type="number"
                  min="0.01"
                  step="0.01"
                  value={draft.amount}
                  onChange={(e) =>
                    setDraft({ ...draft, amount: e.target.value })
                  }
                  placeholder="Enter amount in PKR"
                />
              </label>
            ) : (
              <label>
                Reason
                <input
                  value={draft.reason}
                  onChange={(e) =>
                    setDraft({ ...draft, reason: e.target.value })
                  }
                  placeholder="Receipt is invalid or amount not received"
                />
              </label>
            )}
            <div>
              <button onClick={() => setDialog(null)}>Cancel</button>
              <button
                className={
                  dialog.action === "approve" ? "blue" : "danger-action"
                }
                disabled={busy === dialog.row.id}
                onClick={() => void decide()}
              >
                {busy === dialog.row.id
                  ? "Saving..."
                  : dialog.action === "approve"
                  ? "Confirm credit"
                  : "Confirm rejection"}
              </button>
            </div>
          </article>
        </div>
      )}
    </section>
  );
}

function Overview({
  doctors,
  patients,
  consultations,
  verified,
  pending,
  incomplete,
  go,
}: {
  doctors: U[];
  patients: U[];
  consultations: C[];
  verified: number;
  pending: number;
  incomplete: number;
  go: (t: T) => void;
}) {
  const active = consultations.filter((x) =>
      ["pending", "accepted", "inProgress"].includes(x.status),
    ).length,
    follow = consultations.filter((x) => x.follow_up_date).length,
    completed = consultations.filter((x) => x.status === "completed").length,
    cancelled = consultations.filter((x) =>
      ["cancelled", "canceled"].includes(x.status),
    ).length;
  return (
    <div className="overview-dashboard">
      <section className="overview-hero">
        <div>
          <p>PLATFORM COMMAND CENTER</p>
          <h2>Care operations, clearly managed.</h2>
          <span>
            Monitor clinical availability, patient demand, and items that need
            your team’s attention.
          </span>
        </div>
        <button className="blue" onClick={() => go("verification")}>
          Review verification queue
          <ArrowRight />
        </button>
      </section>
      <div className="overview-metrics">
        <Metric
          icon={<Users />}
          label="Registered patients"
          value={patients.length}
          note="Total platform accounts"
        />
        <Metric
          icon={<Stethoscope />}
          label="Verified doctors"
          value={verified}
          note={`${doctors.length} total doctor accounts`}
        />
        <Metric
          icon={<ClipboardList />}
          label="Consultations"
          value={consultations.length}
          note={`${completed} completed · ${cancelled} cancelled`}
        />
        <Metric
          icon={<CalendarClock />}
          label="Follow-up care"
          value={follow}
          note="Scheduled follow-up sessions"
        />
      </div>
      <div className="overview-grid">
        <section className="overview-card priority">
          <div className="overview-card-head">
            <div>
              <p>PRIORITY QUEUE</p>
              <h3>Needs attention</h3>
            </div>
            <AlertTriangle />
          </div>
          <button onClick={() => go("verification")}>
            <span>
              <b>{pending} doctor profiles</b>
              <small>waiting for verification review</small>
            </span>
            <ArrowRight />
          </button>
          <button onClick={() => go("doctors")}>
            <span>
              <b>{incomplete} verified doctors</b>
              <small>have incomplete public profiles</small>
            </span>
            <ArrowRight />
          </button>
          <button onClick={() => go("followups")}>
            <span>
              <b>{follow} follow-up sessions</b>
              <small>need care-continuity monitoring</small>
            </span>
            <ArrowRight />
          </button>
        </section>
        <section className="overview-card activity">
          <div className="overview-card-head">
            <div>
              <p>CARE ACTIVITY</p>
              <h3>Consultation health</h3>
            </div>
            <CheckCircle2 />
          </div>
          <div className="activity-summary activity-summary-four">
            <div>
              <strong>{completed}</strong>
              <span>Completed consultations</span>
            </div>
            <div>
              <strong>{cancelled}</strong>
              <span>Cancelled consultations</span>
            </div>
            <div>
              <strong>{active}</strong>
              <span>Open consultations</span>
            </div>
            <div>
              <strong>
                {consultations.length
                  ? Math.round((completed / consultations.length) * 100)
                  : 0}
                %
              </strong>
              <span>Completion rate</span>
            </div>
          </div>
          <button
            className="outline-action"
            onClick={() => go("consultations")}
          >
            Open consultation history
            <ArrowRight />
          </button>
        </section>
      </div>
      <section className="overview-card recent">
        <div className="overview-card-head">
          <div>
            <p>RECENT CONSULTATIONS</p>
            <h3>Latest platform activity</h3>
          </div>
          <button onClick={() => go("consultations")}>View all</button>
        </div>
        {consultations.slice(0, 5).map((x) => (
          <a
            href={`/consultations/${x.id}`}
            className="overview-row"
            key={x.id}
          >
            <span>
              <b>{x.doctor?.name || "Doctor"}</b>
              <small>with {x.patient?.name || "Patient"}</small>
            </span>
            <i className={`status ${x.status}`}>{x.status}</i>
            <strong>Rs. {x.consultation_fee}</strong>
            <small>
              {new Date(x.completed_at ?? x.created_at).toLocaleDateString()}
            </small>
          </a>
        ))}
        {!consultations.length && (
          <p className="detail-empty">No consultations recorded yet.</p>
        )}
      </section>
    </div>
  );
}
function Metric({
  icon,
  label,
  value,
  note,
}: {
  icon: React.ReactNode;
  label: string;
  value: number;
  note: string;
}) {
  return (
    <article>
      <i>{icon}</i>
      <span>
        <small>{label}</small>
        <strong>{value}</strong>
        <em>{note}</em>
      </span>
    </article>
  );
}
function History({ rows }: { rows: C[] }) {
  const completed = rows.filter((x) => x.status === "completed").length,
    cancelled = rows.filter((x) => ["cancelled", "canceled"].includes(x.status))
      .length,
    open = rows.filter((x) =>
      ["pending", "accepted", "inProgress"].includes(x.status),
    ).length,
    rate = rows.length ? Math.round((completed / rows.length) * 100) : 0;
  return (
    <>
      <section className="history-summary">
        <article>
          <small>Total consultations</small>
          <strong>{rows.length}</strong>
        </article>
        <article className="history-completed">
          <small>Completed</small>
          <strong>{completed}</strong>
        </article>
        <article className="history-cancelled">
          <small>Cancelled</small>
          <strong>{cancelled}</strong>
        </article>
        <article className="history-open">
          <small>Open consultations</small>
          <strong>{open}</strong>
        </article>
        <article>
          <small>Completion rate</small>
          <strong>{rate}%</strong>
        </article>
      </section>
      <div className="history-table">
        <div className="history-head">
          <span>Doctor</span>
          <span>Patient</span>
          <span>Status</span>
          <span>Fee</span>
          <span>Date</span>
        </div>
        {rows.map((x) => (
          <a
            key={x.id}
            className="history-row consultation-link"
            href={`/consultations/${x.id}`}
          >
            <span>{x.doctor?.name || "—"}</span>
            <span>{x.patient?.name || "—"}</span>
            <i className={`status ${x.status}`}>{x.status}</i>
            <span>Rs. {x.consultation_fee}</span>
            <span>
              {new Date(x.completed_at ?? x.created_at).toLocaleDateString()}
            </span>
          </a>
        ))}
        {!rows.length && (
          <p className="detail-empty">No consultation records found.</p>
        )}
      </div>
    </>
  );
}

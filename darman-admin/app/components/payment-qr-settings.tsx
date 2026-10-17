"use client";

import { useCallback, useEffect, useState } from "react";
import { ImagePlus, RefreshCw, Upload } from "lucide-react";

type Settings = { qr_url: string | null; updated_at: string | null };

export default function PaymentQrSettings({ token }: { token: string }) {
  const [settings, setSettings] = useState<Settings>({ qr_url: null, updated_at: null });
  const [file, setFile] = useState<File | null>(null);
  const [loading, setLoading] = useState(true);
  const [uploading, setUploading] = useState(false);
  const [notice, setNotice] = useState("");

  const load = useCallback(async () => {
    setLoading(true);
    const response = await fetch("/api/admin/payment-qr", { headers: { Authorization: `Bearer ${token}` } });
    const data = await response.json();
    if (response.ok) setSettings(data);
    else setNotice(data.error ?? "Could not load the payment QR.");
    setLoading(false);
  }, [token]);
  useEffect(() => { void load(); }, [load]);

  const upload = async () => {
    if (!file) { setNotice("Choose the QR image first."); return; }
    setUploading(true); setNotice("");
    const form = new FormData(); form.set("file", file);
    const response = await fetch("/api/admin/payment-qr", { method: "POST", headers: { Authorization: `Bearer ${token}` }, body: form });
    const data = await response.json();
    setUploading(false);
    if (!response.ok) { setNotice(data.error ?? "QR image could not be uploaded."); return; }
    setSettings(data); setFile(null); setNotice("Payment QR updated. It will appear in the patient app.");
  };

  return <section className="payment-qr-page">
    <section className="payment-qr-intro"><div><ImagePlus/><span><small>WALLET PAYMENT SETTINGS</small><h2>JazzCash payment QR</h2><p>Upload the QR image patients see when they choose manual wallet top-up. The latest image is served by the app server.</p></span></div></section>
    <section className="payment-qr-panel">
      <div className="payment-qr-preview">
        {loading ? <p>Loading current QR...</p> : settings.qr_url ? <img src={settings.qr_url} alt="Current JazzCash payment QR"/> : <div className="payment-qr-empty"><ImagePlus/><b>No payment QR uploaded</b><span>Upload an image to show it in the patient app.</span></div>}
      </div>
      <div className="payment-qr-controls">
        <label className="payment-qr-file">{file ? file.name : "Choose a QR image"}<input type="file" accept="image/jpeg,image/png,image/webp" onChange={event => setFile(event.target.files?.[0] ?? null)}/></label>
        <small>JPG, PNG, or WebP. Maximum size 5 MB.</small>
        {settings.updated_at && <small>Last updated {new Date(settings.updated_at).toLocaleString()}</small>}
        {notice && <p className="payment-qr-notice">{notice}</p>}
        <div className="payment-qr-actions"><button onClick={() => void load()} disabled={loading || uploading}><RefreshCw/>Refresh</button><button className="blue" onClick={() => void upload()} disabled={uploading || !file}>{uploading ? <i/> : <Upload/>}{uploading ? "Uploading..." : "Upload QR"}</button></div>
      </div>
    </section>
  </section>;
}

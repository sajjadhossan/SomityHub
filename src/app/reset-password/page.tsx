"use client";

import { FormEvent, useEffect, useState } from "react";
import { getSupabaseBrowserClient } from "@/lib/supabase";

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [ready, setReady] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");

  useEffect(() => {
    try {
      const supabase = getSupabaseBrowserClient();
      supabase.auth.getSession().then(({ data }) => setReady(Boolean(data.session)));
      const { data } = supabase.auth.onAuthStateChange((_event, session) => setReady(Boolean(session)));
      return () => data.subscription.unsubscribe();
    } catch {
      setError("Supabase configuration পাওয়া যায়নি।");
    }
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");
    setMessage("");
    try {
      if (password.length < 8) throw new Error("Password কমপক্ষে ৮ অক্ষরের হতে হবে।");
      const { error: updateError } = await getSupabaseBrowserClient().auth.updateUser({ password });
      if (updateError) throw updateError;
      setMessage("Password update হয়েছে। এখন মূল Login Page-এ গিয়ে Login করুন।");
      setPassword("");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Password update করা যায়নি।");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="auth-panel" style={{ minHeight: "100vh" }}>
      <section className="auth-card">
        <div className="brand">SomitiPro</div>
        <h2 style={{ marginTop: 32 }}>নতুন Password সেট করুন</h2>
        <p className="subheading">Email-এর password reset link থেকে এই Page-এ আসতে হবে।</p>
        {ready ? (
          <form onSubmit={handleSubmit}>
            <div className="field">
              <label htmlFor="newPassword">নতুন Password</label>
              <input id="newPassword" type="password" minLength={8} required value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="new-password" placeholder="কমপক্ষে ৮ অক্ষর" />
            </div>
            <button className="primary-button" disabled={busy}>{busy ? "আপডেট হচ্ছে..." : "Password Update করুন"}</button>
          </form>
        ) : (
          <div className="form-message">Reset session পাওয়া যায়নি। Email-এর সর্বশেষ reset link আবার খুলুন।</div>
        )}
        {message && <div className="form-message" role="status">{message}</div>}
        {error && <div className="form-message form-error" role="alert">{error}</div>}
        <p className="small-note"><a href="/">মূল Login Page-এ ফিরে যান</a></p>
      </section>
    </main>
  );
}

"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase";

type Mode = "login" | "signup";

export default function HomePage() {
  const router = useRouter();
  const [mode, setMode] = useState<Mode>("login");
  const [displayName, setDisplayName] = useState("");
  const [email, setEmail] = useState("");
  const [password, setPassword] = useState("");
  const [busy, setBusy] = useState(false);
  const [message, setMessage] = useState("");
  const [error, setError] = useState("");
  const [userEmail, setUserEmail] = useState<string | null>(null);
  const [configured, setConfigured] = useState(true);

  useEffect(() => {
    try {
      const supabase = getSupabaseBrowserClient();
      supabase.auth.getSession().then(({ data, error: sessionError }) => {
        if (sessionError) setError(sessionError.message);
        setUserEmail(data.session?.user.email ?? null);
      });
      const { data } = supabase.auth.onAuthStateChange((_event, session) => {
        setUserEmail(session?.user.email ?? null);
      });
      return () => data.subscription.unsubscribe();
    } catch {
      setConfigured(false);
    }
  }, []);

  async function handleSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setBusy(true);
    setError("");
    setMessage("");

    try {
      const supabase = getSupabaseBrowserClient();
      if (mode === "signup") {
        if (displayName.trim().length < 2) throw new Error("নাম কমপক্ষে ২ অক্ষরের হতে হবে।");
        if (password.length < 8) throw new Error("Password কমপক্ষে ৮ অক্ষরের হতে হবে।");

        const { data, error: authError } = await supabase.auth.signUp({
          email: email.trim(),
          password,
          options: {
            data: { display_name: displayName.trim(), preferred_language: "bn" },
            emailRedirectTo: window.location.origin
          }
        });
        if (authError) throw authError;
        if (data.session) {
          setMessage("Registration সফল হয়েছে। আপনার Profile স্বয়ংক্রিয়ভাবে তৈরি হওয়ার কথা।");
        } else {
          setMessage("Registration request সফল। Email inbox থেকে confirmation link খুলুন, তারপর Login করুন।");
        }
      } else {
        const { error: authError } = await supabase.auth.signInWithPassword({
          email: email.trim(),
          password
        });
        if (authError) throw authError;
        router.push("/committees");
      }
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "একটি অপ্রত্যাশিত সমস্যা হয়েছে।");
    } finally {
      setBusy(false);
    }
  }

  async function handleReset() {
    setError("");
    setMessage("");
    if (!email.trim()) {
      setError("Password reset link পাঠাতে আগে Email দিন।");
      return;
    }
    setBusy(true);
    try {
      const supabase = getSupabaseBrowserClient();
      const { error: resetError } = await supabase.auth.resetPasswordForEmail(email.trim(), {
        redirectTo: `${window.location.origin}/reset-password`
      });
      if (resetError) throw resetError;
      setMessage("Email address-টি registered থাকলে password reset link পাঠানো হয়েছে।");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Reset request পাঠানো যায়নি।");
    } finally {
      setBusy(false);
    }
  }

  async function handleLogout() {
    setBusy(true);
    setError("");
    try {
      const { error: logoutError } = await getSupabaseBrowserClient().auth.signOut();
      if (logoutError) throw logoutError;
      setMessage("Logout সফল হয়েছে।");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Logout করা যায়নি।");
    } finally {
      setBusy(false);
    }
  }

  return (
    <main className="page-shell">
      <section className="intro-panel">
        <div className="brand">SomitiPro</div>
        <div className="intro-copy">
          <h1>সমিতির হিসাব,<br />এখন আরও সহজ।</h1>
          <p>সদস্য, জমা, উত্তোলন ও কমিটির কার্যক্রম—একটি নিরাপদ ও সংগঠিত প্ল্যাটফর্মে পরিচালনা করুন।</p>
        </div>
        <div className="intro-foot">বাংলা ও English interface · BDT · Secure access</div>
      </section>

      <section className="auth-panel">
        <div className="auth-card">
          {userEmail ? (
            <>
              <h2>স্বাগতম</h2>
              <p className="subheading">আপনি এই Account দিয়ে Login আছেন: <strong>{userEmail}</strong></p>
              <div className="form-message">Authentication session active.</div>
              <button className="primary-button" onClick={handleLogout} disabled={busy}>Logout</button>
            </>
          ) : (
            <>
              <h2>{mode === "login" ? "আপনার Account-এ প্রবেশ করুন" : "নতুন Account তৈরি করুন"}</h2>
              <p className="subheading">SomitiPro ব্যবহার শুরু করতে নিচের তথ্য দিন।</p>

              <div className="tabs" role="tablist" aria-label="Authentication mode">
                <button type="button" role="tab" aria-selected={mode === "login"} onClick={() => { setMode("login"); setError(""); setMessage(""); }}>Login</button>
                <button type="button" role="tab" aria-selected={mode === "signup"} onClick={() => { setMode("signup"); setError(""); setMessage(""); }}>Registration</button>
              </div>

              {!configured && (
                <div className="form-message form-error">
                  Supabase configuration পাওয়া যায়নি। Deployment environment-এ .env.example অনুযায়ী URL এবং publishable key সেট করুন।
                </div>
              )}

              <form onSubmit={handleSubmit}>
                {mode === "signup" && (
                  <div className="field">
                    <label htmlFor="displayName">পূর্ণ নাম</label>
                    <input id="displayName" value={displayName} onChange={(e) => setDisplayName(e.target.value)} autoComplete="name" required minLength={2} placeholder="আপনার নাম" />
                  </div>
                )}
                <div className="field">
                  <label htmlFor="email">Email Address</label>
                  <input id="email" type="email" value={email} onChange={(e) => setEmail(e.target.value)} autoComplete="email" required placeholder="name@example.com" />
                </div>
                <div className="field">
                  <label htmlFor="password">Password</label>
                  <input id="password" type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete={mode === "login" ? "current-password" : "new-password"} required minLength={8} placeholder="কমপক্ষে ৮ অক্ষর" />
                </div>
                <button className="primary-button" type="submit" disabled={busy || !configured}>
                  {busy ? "অপেক্ষা করুন..." : mode === "login" ? "Login করুন" : "Account তৈরি করুন"}
                </button>
              </form>

              {mode === "login" && <button className="text-button" type="button" onClick={handleReset} disabled={busy}>Password ভুলে গেছেন?</button>}
              {message && <div className="form-message" role="status">{message}</div>}
              {error && <div className="form-message form-error" role="alert">{error}</div>}
              <p className="small-note">Registration-এর পর Email confirmation চালু থাকলে Inbox থেকে link verify করতে হবে। Password কখনো আমাদের কাছে পাঠাবেন না।</p>
            </>
          )}
          {userEmail && message && <div className="form-message" role="status">{message}</div>}
          {error && <div className="form-message form-error" role="alert">{error}</div>}
        </div>
      </section>
    </main>
  );
}

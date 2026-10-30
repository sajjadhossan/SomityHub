"use client";

import { FormEvent, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase";

type Profile = { id: string; display_name: string; preferred_language: "bn" | "en"; created_at: string };

export default function ProfilePage() {
  const router = useRouter();
  const [profile, setProfile] = useState<Profile | null>(null);
  const [displayName, setDisplayName] = useState("");
  const [language, setLanguage] = useState<"bn" | "en">("bn");
  const [email, setEmail] = useState("");
  const [busy, setBusy] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  useEffect(() => {
    let active = true;
    async function load() {
      try {
        const supabase = getSupabaseBrowserClient();
        const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
        if (sessionError) throw sessionError;
        const user = sessionData.session?.user;
        if (!user) { router.replace("/"); return; }
        setEmail(user.email ?? "");
        const { data, error: profileError } = await supabase
          .from("profiles")
          .select("id,display_name,preferred_language,created_at")
          .eq("id", user.id)
          .maybeSingle();
        if (profileError) throw profileError;
        if (!data) throw new Error("আপনার Profile record পাওয়া যায়নি। Support/Admin-এর সহায়তা নিন।");
        if (active) {
          const row = data as Profile;
          setProfile(row);
          setDisplayName(row.display_name ?? "");
          setLanguage(row.preferred_language ?? "bn");
        }
      } catch (caught) {
        if (active) setError(caught instanceof Error ? caught.message : "Profile load করা যায়নি।");
      } finally {
        if (active) setBusy(false);
      }
    }
    void load();
    return () => { active = false; };
  }, [router]);

  async function handleSave(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!profile) return;
    setSaving(true); setError(""); setNotice("");
    try {
      const name = displayName.trim();
      if (name.length < 2) throw new Error("নাম কমপক্ষে ২ অক্ষরের হতে হবে।");
      const { data, error: updateError } = await getSupabaseBrowserClient()
        .from("profiles")
        .update({ display_name: name, preferred_language: language })
        .eq("id", profile.id)
        .select("id,display_name,preferred_language,created_at")
        .single();
      if (updateError) throw updateError;
      setProfile(data as Profile);
      setDisplayName(name);
      setNotice("Profile সফলভাবে আপডেট হয়েছে।");
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Profile update করা যায়নি।");
    } finally {
      setSaving(false);
    }
  }

  async function handleLogout() {
    const { error: logoutError } = await getSupabaseBrowserClient().auth.signOut();
    if (logoutError) { setError(logoutError.message); return; }
    router.replace("/");
  }

  return (
    <main className="workspace-shell">
      <header className="workspace-header">
        <a className="brand" href="/committees">SomitiPro</a>
        <button className="text-button" type="button" onClick={handleLogout}>Logout</button>
      </header>
      <section className="workspace-content">
        <div className="workspace-heading">
          <p className="eyebrow">ACCOUNT SETTINGS</p>
          <h1>আপনার Profile</h1>
          <p className="subheading">আপনার ব্যক্তিগত Account information ও ভাষা পছন্দ পরিচালনা করুন।</p>
        </div>
        <section className="workspace-card">
          {busy ? <p className="card-description">Profile load হচ্ছে...</p> : (
            <>
              <div className="field">
                <label>Email Address</label>
                <input value={email} readOnly aria-readonly="true" />
                <span className="field-hint">Email এই পেজ থেকে পরিবর্তন করা যাবে না।</span>
              </div>
              <form onSubmit={handleSave}>
                <div className="field">
                  <label htmlFor="profileName">পূর্ণ নাম</label>
                  <input id="profileName" value={displayName} onChange={(event) => setDisplayName(event.target.value)} minLength={2} maxLength={120} required autoComplete="name" />
                </div>
                <div className="field">
                  <label htmlFor="profileLanguage">Interface Language</label>
                  <select id="profileLanguage" value={language} onChange={(event) => setLanguage(event.target.value as "bn" | "en")}>
                    <option value="bn">বাংলা</option>
                    <option value="en">English</option>
                  </select>
                </div>
                <button className="primary-button" type="submit" disabled={saving || !profile}>{saving ? "সংরক্ষণ হচ্ছে..." : "Profile সংরক্ষণ করুন"}</button>
              </form>
            </>
          )}
          {notice && <div className="form-message" role="status">{notice}</div>}
          {error && <div className="form-message form-error" role="alert">{error}</div>}
          <button className="text-button" type="button" onClick={() => router.push("/committees")}>Committee Workspace-এ ফিরে যান</button>
        </section>
      </section>
    </main>
  );
}

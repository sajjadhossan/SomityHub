"use client";

import { FormEvent, useCallback, useEffect, useState } from "react";
import { useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase";

type Committee = {
  id: string;
  name: string;
  slug: string;
  currency_code: string;
  timezone: string;
  created_at: string;
};

export default function CommitteesPage() {
  const router = useRouter();
  const [committees, setCommittees] = useState<Committee[]>([]);
  const [name, setName] = useState("");
  const [slug, setSlug] = useState("");
  const [loading, setLoading] = useState(true);
  const [saving, setSaving] = useState(false);
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const loadCommittees = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const supabase = getSupabaseBrowserClient();
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session) {
        router.replace("/");
        return;
      }

      const { data, error: queryError } = await supabase
        .from("organizations")
        .select("id,name,slug,currency_code,timezone,created_at")
        .order("created_at", { ascending: false });

      if (queryError) throw queryError;
      setCommittees((data ?? []) as Committee[]);
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Committee list load করা যায়নি।");
    } finally {
      setLoading(false);
    }
  }, [router]);

  useEffect(() => {
    void loadCommittees();
  }, [loadCommittees]);

  async function handleCreate(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setSaving(true);
    setError("");
    setNotice("");

    try {
      const supabase = getSupabaseBrowserClient();
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      if (!sessionData.session) {
        router.replace("/");
        return;
      }

      const { data, error: rpcError } = await supabase.rpc("create_committee", {
        p_name: name.trim(),
        p_slug: slug.trim()
      });
      if (rpcError) throw rpcError;

      const created = Array.isArray(data) ? data[0] : data;
      if (!created?.organization_id || !created?.owner_member_code) {
        throw new Error("Committee তৈরি হয়েছে কি না নিশ্চিত করা যায়নি। Database response যাচাই করুন।");
      }

      setName("");
      setSlug("");
      setNotice(`Committee তৈরি হয়েছে। আপনার Admin Member ID: ${created.owner_member_code}`);
      await loadCommittees();
    } catch (caught) {
      setError(caught instanceof Error ? caught.message : "Committee তৈরি করা যায়নি।");
    } finally {
      setSaving(false);
    }
  }

  async function handleLogout() {
    const { error: logoutError } = await getSupabaseBrowserClient().auth.signOut();
    if (logoutError) {
      setError(logoutError.message);
      return;
    }
    router.replace("/");
  }

  return (
    <main className="workspace-shell">
      <header className="workspace-header">
        <a className="brand" href="/">SomitiPro</a>
        <div style={{ display: "flex", alignItems: "center", gap: 18 }}>
          <button className="text-button" type="button" onClick={() => router.push("/profile")}>আমার Profile</button>
          <button className="text-button" type="button" onClick={handleLogout}>Logout</button>
        </div>
      </header>

      <section className="workspace-content">
        <div className="workspace-heading">
          <div>
            <p className="eyebrow">WORKSPACE</p>
            <h1>আপনার Committee</h1>
            <p className="subheading">আপনার তৈরি করা এবং যেখানে আপনি সদস্য—সেসব Committee এখানে দেখাবে।</p>
          </div>
        </div>

        <section className="workspace-card">
          <h2>নতুন Committee তৈরি করুন</h2>
          <p className="card-description">তৈরি করা Account-টি স্বয়ংক্রিয়ভাবে এই Committee-এর Committee Admin হবে।</p>
          <form onSubmit={handleCreate}>
            <div className="field">
              <label htmlFor="committeeName">Committee Name</label>
              <input id="committeeName" value={name} onChange={(event) => setName(event.target.value)} required minLength={2} maxLength={120} placeholder="যেমন: আলোর দিশারী সমবায় সমিতি" />
            </div>
            <div className="field">
              <label htmlFor="committeeSlug">Committee Slug (English)</label>
              <input id="committeeSlug" value={slug} onChange={(event) => setSlug(event.target.value.toLowerCase().replace(/[^a-z0-9-]/g, "-").replace(/-+/g, "-"))} required minLength={3} maxLength={80} pattern="[a-z0-9]+(-[a-z0-9]+)*" placeholder="alor-dishari" />
              <span className="field-hint">URL-friendly unique name; English letters, numbers ও hyphen ব্যবহার করুন।</span>
            </div>
            <button className="primary-button" type="submit" disabled={saving}>{saving ? "তৈরি হচ্ছে..." : "Committee তৈরি করুন"}</button>
          </form>
          {notice && <div className="form-message" role="status">{notice}</div>}
          {error && <div className="form-message form-error" role="alert">{error}</div>}
        </section>

        <section className="workspace-card">
          <div className="section-title-row">
            <h2>Committee List</h2>
            <button className="text-button" type="button" onClick={() => void loadCommittees()} disabled={loading}>Refresh</button>
          </div>
          {loading ? <p className="card-description">Committee list load হচ্ছে...</p> :
            committees.length === 0 ? <p className="card-description">এখনো কোনো Committee পাওয়া যায়নি। উপরের Form দিয়ে প্রথম Committee তৈরি করুন।</p> :
            <div className="committee-list">
              {committees.map((committee) => (
                <article className="committee-item" key={committee.id}>
                  <div>
                    <h3>{committee.name}</h3>
                    <p>{committee.slug}</p>
                    <span>{committee.currency_code} · {committee.timezone}</span>
                  </div>
                  <div className="committee-card-actions">
                    <span className="committee-date">{new Date(committee.created_at).toLocaleDateString("bn-BD")}</span>
                    <button className="primary-button committee-open-button" type="button" onClick={() => router.push(`/committees/${committee.id}`)}>Manage Committee</button>
                  </div>
                </article>
              ))}
            </div>
          }
        </section>
      </section>
    </main>
  );
}

"use client";

import { FormEvent, useCallback, useEffect, useMemo, useState } from "react";
import { useParams, useRouter } from "next/navigation";
import { getSupabaseBrowserClient } from "@/lib/supabase";

type Membership = {
  id: string;
  user_id: string;
  member_code: string;
  role: string;
  is_active: boolean;
  joined_at: string;
  phone?: string | null;
  address?: string | null;
};

const ROLES = [
  { value: "committee_admin", label: "Committee Admin" },
  { value: "manager", label: "Manager" },
  { value: "treasurer", label: "Treasurer" },
  { value: "secretary", label: "Secretary" },
  { value: "auditor", label: "Auditor" },
  { value: "member", label: "Member" }
];

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : "একটি অপ্রত্যাশিত সমস্যা হয়েছে।";
}

export default function CommitteeAdminPage() {
  const params = useParams<{ organizationId: string }>();
  const organizationId = params.organizationId;
  const router = useRouter();
  const [committeeName, setCommitteeName] = useState("");
  const [members, setMembers] = useState<Membership[]>([]);
  const [currentUserId, setCurrentUserId] = useState("");
  const [currentRole, setCurrentRole] = useState("");
  const [loading, setLoading] = useState(true);
  const [savingMember, setSavingMember] = useState(false);
  const [adding, setAdding] = useState(false);
  const [userId, setUserId] = useState("");
  const [phone, setPhone] = useState("");
  const [address, setAddress] = useState("");
  const [search, setSearch] = useState("");
  const [error, setError] = useState("");
  const [notice, setNotice] = useState("");

  const isAdmin = currentRole === "committee_admin";
  const canManageMembers = isAdmin || currentRole === "manager";

  const loadData = useCallback(async () => {
    setLoading(true);
    setError("");
    try {
      const supabase = getSupabaseBrowserClient();
      const { data: sessionData, error: sessionError } = await supabase.auth.getSession();
      if (sessionError) throw sessionError;
      const user = sessionData.session?.user;
      if (!user) {
        router.replace("/");
        return;
      }
      setCurrentUserId(user.id);

      const { data: organization, error: organizationError } = await supabase
        .from("organizations")
        .select("id,name")
        .eq("id", organizationId)
        .maybeSingle();
      if (organizationError) throw organizationError;
      if (!organization) throw new Error("Committee পাওয়া যায়নি অথবা আপনার access নেই।");
      setCommitteeName(organization.name);

      const { data: membershipRows, error: membershipError } = await supabase
        .from("committee_memberships")
        .select("id,user_id,member_code,role,is_active,joined_at")
        .eq("organization_id", organizationId)
        .order("joined_at", { ascending: false });
      if (membershipError) throw membershipError;

      const rows = (membershipRows ?? []) as Membership[];
      const actor = rows.find((row) => row.user_id === user.id && row.is_active);
      if (!actor || !["committee_admin", "manager"].includes(actor.role)) {
        throw new Error("এই Committee পরিচালনার অনুমতি আপনার নেই।");
      }
      setCurrentRole(actor.role);

      const { data: details, error: detailsError } = await supabase
        .from("member_details")
        .select("membership_id,phone,address")
        .eq("organization_id", organizationId);
      if (detailsError) throw detailsError;
      const detailMap = new Map((details ?? []).map((item) => [item.membership_id, item]));
      setMembers(rows.map((row) => ({
        ...row,
        phone: detailMap.get(row.id)?.phone ?? null,
        address: detailMap.get(row.id)?.address ?? null
      })));
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setLoading(false);
    }
  }, [organizationId, router]);

  useEffect(() => { void loadData(); }, [loadData]);

  const filteredMembers = useMemo(() => {
    const query = search.trim().toLowerCase();
    if (!query) return members;
    return members.filter((member) =>
      [member.member_code, member.role, member.phone ?? "", member.address ?? ""]
        .some((value) => value.toLowerCase().includes(query))
    );
  }, [members, search]);

  async function handleAddMember(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setAdding(true);
    setError("");
    setNotice("");
    try {
      const supabase = getSupabaseBrowserClient();
      const { data, error: rpcError } = await supabase.rpc("add_committee_member", {
        p_organization_id: organizationId,
        p_user_id: userId.trim(),
        p_phone: phone.trim() || null,
        p_address: address.trim() || null
      });
      if (rpcError) throw rpcError;
      const result = Array.isArray(data) ? data[0] : data;
      setNotice(result?.member_code
        ? `সদস্য যোগ হয়েছে। Member Code: ${result.member_code}`
        : "সদস্য যোগ করার request সফল হয়েছে।");
      setUserId("");
      setPhone("");
      setAddress("");
      await loadData();
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setAdding(false);
    }
  }

  async function handleRoleChange(member: Membership, newRole: string) {
    if (!isAdmin || member.user_id === currentUserId || member.role === newRole) return;
    const oldRole = member.role;
    const confirmed = window.confirm(
      `${member.member_code}-এর role "${oldRole}" থেকে "${newRole}" করতে চান?`
    );
    if (!confirmed) return;

    setSavingMember(true);
    setError("");
    setNotice("");
    try {
      const { error: rpcError } = await getSupabaseBrowserClient().rpc(
        "admin_update_committee_member_role",
        {
          p_organization_id: organizationId,
          p_membership_id: member.id,
          p_new_role: newRole
        }
      );
      if (rpcError) throw rpcError;
      setNotice(`${member.member_code}-এর role সফলভাবে ${newRole} করা হয়েছে। Audit log record তৈরি হয়েছে।`);
      await loadData();
    } catch (caught) {
      setError(errorMessage(caught));
    } finally {
      setSavingMember(false);
    }
  }

  const activeCount = members.filter((member) => member.is_active).length;
  const roleLabel = (role: string) => ROLES.find((item) => item.value === role)?.label ?? role;

  return (
    <main className="workspace-shell">
      <header className="workspace-header">
        <a className="brand" href="/">SomitiPro</a>
        <div className="admin-header-actions">
          <button className="text-button" type="button" onClick={() => router.push("/committees")}>Committee List</button>
          <button className="text-button" type="button" onClick={() => router.push("/profile")}>আমার Profile</button>
        </div>
      </header>

      <section className="workspace-content admin-content">
        <div className="workspace-heading">
          <p className="eyebrow">COMMITTEE WORKSPACE</p>
          <h1>{committeeName || "Committee Management"}</h1>
          <p className="subheading">সদস্য তালিকা, membership details এবং role management।</p>
        </div>

        {notice && <div className="form-message" role="status">{notice}</div>}
        {error && <div className="form-message form-error" role="alert">{error}</div>}

        {loading ? <section className="workspace-card"><p className="card-description">Committee data load হচ্ছে...</p></section> : canManageMembers ? (
          <>
            <div className="admin-stat-grid">
              <article className="workspace-card admin-stat"><span>মোট সদস্য</span><strong>{members.length}</strong></article>
              <article className="workspace-card admin-stat"><span>সক্রিয় সদস্য</span><strong>{activeCount}</strong></article>
              <article className="workspace-card admin-stat"><span>আপনার Permission</span><strong>{isAdmin ? "Admin" : "Manager"}</strong></article>
            </div>

            <section className="workspace-card">
              <h2>নতুন সদস্য যোগ করুন</h2>
              <p className="card-description">সদস্যের আগে থেকে SomitiPro account থাকতে হবে। তার Account UUID প্রয়োজন। নতুন সদস্য defaultভাবে Member role পাবে।</p>
              <form onSubmit={handleAddMember}>
                <div className="field">
                  <label htmlFor="memberUserId">User UUID</label>
                  <input id="memberUserId" value={userId} onChange={(event) => setUserId(event.target.value)} required pattern="[0-9a-fA-F-]{36}" placeholder="xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx" />
                </div>
                <div className="admin-form-grid">
                  <div className="field">
                    <label htmlFor="memberPhone">মোবাইল (ঐচ্ছিক)</label>
                    <input id="memberPhone" value={phone} onChange={(event) => setPhone(event.target.value)} maxLength={40} />
                  </div>
                  <div className="field">
                    <label htmlFor="memberAddress">ঠিকানা (ঐচ্ছিক)</label>
                    <input id="memberAddress" value={address} onChange={(event) => setAddress(event.target.value)} maxLength={300} />
                  </div>
                </div>
                <button className="primary-button admin-submit" type="submit" disabled={adding || !canManageMembers}>{adding ? "যোগ হচ্ছে..." : "সদস্য যোগ করুন"}</button>
              </form>
            </section>

            <section className="workspace-card">
              <div className="section-title-row admin-member-heading">
                <div><h2>সদস্য তালিকা</h2><p className="card-description">Role পরিবর্তন শুধু Committee Admin করতে পারবেন। Manager সদস্য যোগ ও তালিকা দেখতে পারবেন।</p></div>
                <button className="text-button" type="button" onClick={() => void loadData()} disabled={loading}>Refresh</button>
              </div>
              <div className="field">
                <label htmlFor="memberSearch">সদস্য খুঁজুন</label>
                <input id="memberSearch" value={search} onChange={(event) => setSearch(event.target.value)} placeholder="Member Code, role, phone বা address" />
              </div>
              {filteredMembers.length === 0 ? <p className="card-description">কোনো সদস্য পাওয়া যায়নি।</p> : (
                <div className="admin-member-list">
                  {filteredMembers.map((member) => (
                    <article className="admin-member-row" key={member.id}>
                      <div className="admin-member-main">
                        <strong>{member.member_code}</strong>
                        <span>{roleLabel(member.role)} · {member.is_active ? "সক্রিয়" : "নিষ্ক্রিয়"}</span>
                        <small>{member.phone || "Phone নেই"}{member.address ? ` · ${member.address}` : ""}</small>
                        <small>যোগদানের তারিখ: {new Date(member.joined_at).toLocaleDateString("bn-BD")}</small>
                      </div>
                      <div className="admin-role-control">
                        {isAdmin && member.user_id !== currentUserId ? (
                          <select aria-label={`${member.member_code} role`} value={member.role} disabled={savingMember} onChange={(event) => void handleRoleChange(member, event.target.value)}>
                            {ROLES.map((role) => <option key={role.value} value={role.value}>{role.label}</option>)}
                          </select>
                        ) : <span className="role-readonly">{roleLabel(member.role)}{member.user_id === currentUserId ? " · আপনি" : ""}</span>}
                      </div>
                    </article>
                  ))}
                </div>
              )}
            </section>
          </>
        ) : !loading ? (
          <section className="workspace-card"><p className="card-description">এই Committee-এর Admin বা Manager permission প্রয়োজন।</p></section>
        ) : null}
      </section>
    </main>
  );
}

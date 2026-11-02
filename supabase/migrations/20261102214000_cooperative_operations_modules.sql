-- Cooperative operations modules: loans, vouchers, meetings, attendance, and documents.
-- Financial balances remain in the existing deposit/withdrawal ledger; loans are tracked separately.
create table if not exists public.cooperative_loans (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  membership_id uuid not null,
  branch_id uuid not null,
  principal_amount numeric(14,2) not null check (principal_amount > 0),
  interest_rate numeric(7,4) not null default 0 check (interest_rate >= 0 and interest_rate <= 100),
  term_months integer not null check (term_months between 1 and 600),
  purpose text not null check (length(btrim(purpose)) between 3 and 1000),
  status text not null default 'pending' check (status in ('pending','approved','rejected','disbursed','closed','cancelled')),
  requested_by uuid not null references auth.users(id),
  reviewed_by uuid references auth.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint cooperative_loans_member_fk foreign key (organization_id,membership_id) references public.committee_memberships(organization_id,id),
  constraint cooperative_loans_branch_fk foreign key (organization_id,branch_id) references public.organization_branches(organization_id,id),
  constraint cooperative_loans_org_id_unique unique (organization_id,id)
);
create index if not exists cooperative_loans_org_status_idx on public.cooperative_loans(organization_id,status,created_at desc);

create table if not exists public.cooperative_loan_repayments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  loan_id uuid not null,
  amount numeric(14,2) not null check (amount > 0),
  payment_date date not null default current_date,
  reference_number text,
  received_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint cooperative_loan_repayments_loan_fk foreign key (organization_id,loan_id) references public.cooperative_loans(organization_id,id)
);
create index if not exists cooperative_loan_repayments_loan_idx on public.cooperative_loan_repayments(organization_id,loan_id,payment_date);

create table if not exists public.cooperative_vouchers (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null,
  voucher_number text not null,
  voucher_type text not null check (voucher_type in ('income','expense')),
  category text not null check (length(btrim(category)) between 2 and 80),
  amount numeric(14,2) not null check (amount > 0),
  description text not null check (length(btrim(description)) between 2 and 1000),
  transaction_date date not null default current_date,
  status text not null default 'pending' check (status in ('pending','approved','rejected','void')),
  created_by uuid not null references auth.users(id),
  approved_by uuid references auth.users(id),
  approved_at timestamptz,
  created_at timestamptz not null default now(),
  constraint cooperative_vouchers_branch_fk foreign key (organization_id,branch_id) references public.organization_branches(organization_id,id),
  constraint cooperative_vouchers_number_unique unique (organization_id,voucher_number),
  constraint cooperative_vouchers_org_id_unique unique (organization_id,id)
);
create index if not exists cooperative_vouchers_org_date_idx on public.cooperative_vouchers(organization_id,transaction_date desc);

create table if not exists public.cooperative_meetings (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid not null,
  title text not null check (length(btrim(title)) between 2 and 160),
  agenda text,
  location text,
  starts_at timestamptz not null,
  ends_at timestamptz,
  status text not null default 'scheduled' check (status in ('scheduled','completed','cancelled')),
  created_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint cooperative_meetings_branch_fk foreign key (organization_id,branch_id) references public.organization_branches(organization_id,id),
  constraint cooperative_meetings_time_check check (ends_at is null or ends_at > starts_at),
  constraint cooperative_meetings_org_id_unique unique (organization_id,id)
);
create index if not exists cooperative_meetings_org_start_idx on public.cooperative_meetings(organization_id,starts_at desc);

create table if not exists public.cooperative_attendance (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  meeting_id uuid not null,
  membership_id uuid not null,
  attendance_status text not null check (attendance_status in ('present','absent','late','excused')),
  marked_by uuid not null references auth.users(id),
  marked_at timestamptz not null default now(),
  note text,
  constraint cooperative_attendance_meeting_fk foreign key (organization_id,meeting_id) references public.cooperative_meetings(organization_id,id),
  constraint cooperative_attendance_member_fk foreign key (organization_id,membership_id) references public.committee_memberships(organization_id,id),
  constraint cooperative_attendance_unique unique (meeting_id,membership_id)
);

create table if not exists public.cooperative_documents (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_id uuid,
  title text not null check (length(btrim(title)) between 2 and 180),
  document_type text not null check (length(btrim(document_type)) between 2 and 80),
  storage_path text not null,
  mime_type text not null,
  file_size_bytes bigint not null check (file_size_bytes > 0 and file_size_bytes <= 20971520),
  visibility text not null default 'committee' check (visibility in ('committee','managers')),
  uploaded_by uuid not null references auth.users(id),
  created_at timestamptz not null default now(),
  constraint cooperative_documents_branch_fk foreign key (organization_id,branch_id) references public.organization_branches(organization_id,id)
);
create index if not exists cooperative_documents_org_created_idx on public.cooperative_documents(organization_id,created_at desc);

-- A common membership gate for read policies; write policies independently enforce roles/ownership.
alter table public.cooperative_loans enable row level security;
alter table public.cooperative_loan_repayments enable row level security;
alter table public.cooperative_vouchers enable row level security;
alter table public.cooperative_meetings enable row level security;
alter table public.cooperative_attendance enable row level security;
alter table public.cooperative_documents enable row level security;

create policy cooperative_loans_member_read on public.cooperative_loans for select to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.id=membership_id and cm.organization_id=cooperative_loans.organization_id and cm.user_id=(select auth.uid()) and cm.is_active)
 or exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_loans.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','treasurer','accountant','auditor')));
create policy cooperative_loans_member_request on public.cooperative_loans for insert to authenticated
with check (requested_by=(select auth.uid()) and status='pending' and reviewed_by is null and exists(select 1 from public.committee_memberships cm where cm.id=membership_id and cm.organization_id=cooperative_loans.organization_id and cm.user_id=(select auth.uid()) and cm.is_active) and exists(select 1 from public.membership_branch_assignments a join public.organization_branches b on b.id=a.branch_id and b.organization_id=a.organization_id where a.organization_id=cooperative_loans.organization_id and a.membership_id=cooperative_loans.membership_id and a.branch_id=cooperative_loans.branch_id and b.is_active));
create policy cooperative_loan_repayments_finance_read on public.cooperative_loan_repayments for select to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_loan_repayments.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','treasurer','accountant','auditor')));
create policy cooperative_vouchers_finance_read on public.cooperative_vouchers for select to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_vouchers.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','treasurer','accountant','auditor')));
create policy cooperative_vouchers_finance_insert on public.cooperative_vouchers for insert to authenticated
with check (created_by=(select auth.uid()) and status='pending' and approved_by is null and exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_vouchers.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','treasurer','accountant')));
create policy cooperative_meetings_member_read on public.cooperative_meetings for select to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_meetings.organization_id and cm.user_id=(select auth.uid()) and cm.is_active));
create policy cooperative_meetings_manager_write on public.cooperative_meetings for all to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_meetings.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','general_secretary','secretary')))
with check (created_by=(select auth.uid()) and exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_meetings.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','general_secretary','secretary')));
create policy cooperative_attendance_member_read on public.cooperative_attendance for select to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_attendance.organization_id and cm.user_id=(select auth.uid()) and cm.is_active));
create policy cooperative_attendance_manager_write on public.cooperative_attendance for all to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_attendance.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','general_secretary','secretary')))
with check (marked_by=(select auth.uid()) and exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_attendance.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','general_secretary','secretary')));
create policy cooperative_documents_member_read on public.cooperative_documents for select to authenticated
using (exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_documents.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and (cooperative_documents.visibility='committee' or cm.role in ('committee_admin','manager','secretary','general_secretary','auditor'))));
create policy cooperative_documents_manager_insert on public.cooperative_documents for insert to authenticated
with check (uploaded_by=(select auth.uid()) and exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_documents.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','secretary','general_secretary')));
grant select, insert on public.cooperative_loans to authenticated;
grant select on public.cooperative_loan_repayments to authenticated;
grant select, insert on public.cooperative_vouchers to authenticated;
grant select, insert, update, delete on public.cooperative_meetings to authenticated;
grant select, insert, update, delete on public.cooperative_attendance to authenticated;
grant select, insert on public.cooperative_documents to authenticated;

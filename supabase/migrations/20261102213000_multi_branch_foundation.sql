-- Multi-branch foundation. Existing organizations receive one default branch;
-- existing memberships and financial records are assigned without changing balances.

create table if not exists public.organization_branches (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null references public.organizations(id) on delete cascade,
  branch_code text not null,
  name text not null,
  address text,
  phone text,
  is_default boolean not null default false,
  is_active boolean not null default true,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  constraint organization_branches_code_nonempty check (length(btrim(branch_code)) between 1 and 32),
  constraint organization_branches_name_nonempty check (length(btrim(name)) between 2 and 120),
  constraint organization_branches_org_id_unique unique (organization_id, id),
  constraint organization_branches_org_code_unique unique (organization_id, branch_code)
);

create unique index if not exists organization_branches_one_default_per_org
  on public.organization_branches (organization_id) where is_default;

create table if not exists public.membership_branch_assignments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  membership_id uuid not null,
  branch_id uuid not null,
  is_primary boolean not null default false,
  assigned_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  constraint membership_branch_assignments_membership_fk
    foreign key (organization_id, membership_id)
    references public.committee_memberships(organization_id, id) on delete cascade,
  constraint membership_branch_assignments_branch_fk
    foreign key (organization_id, branch_id)
    references public.organization_branches(organization_id, id) on delete cascade,
  constraint membership_branch_assignments_unique unique (membership_id, branch_id)
);

create unique index if not exists membership_branch_one_primary
  on public.membership_branch_assignments (membership_id) where is_primary;

alter table public.financial_transactions
  add column if not exists branch_id uuid;

alter table public.financial_transactions
  add constraint financial_transactions_branch_fk
  foreign key (organization_id, branch_id)
  references public.organization_branches(organization_id, id);

-- Provision one default branch for each existing organization.
insert into public.organization_branches
  (organization_id, branch_code, name, is_default, created_by)
select o.id, 'MAIN', 'প্রধান শাখা', true, o.created_by
from public.organizations o
where not exists (
  select 1 from public.organization_branches b
  where b.organization_id = o.id and b.is_default
)
on conflict (organization_id, branch_code) do nothing;

-- Backfill legacy memberships to the default branch; no membership is moved
-- between organizations and no financial amount is modified.
insert into public.membership_branch_assignments
  (organization_id, membership_id, branch_id, is_primary)
select cm.organization_id, cm.id, b.id, true
from public.committee_memberships cm
join public.organization_branches b
  on b.organization_id = cm.organization_id and b.is_default
on conflict (membership_id, branch_id) do nothing;

update public.financial_transactions ft
set branch_id = b.id
from public.organization_branches b
where b.organization_id = ft.organization_id
  and b.is_default
  and ft.branch_id is null;

alter table public.financial_transactions
  alter column branch_id set not null;

create or replace function public.assign_default_financial_branch()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_branch_id uuid;
begin
  if new.branch_id is not null then
    if not exists (
      select 1 from public.organization_branches b
      where b.id = new.branch_id
        and b.organization_id = new.organization_id
        and b.is_active
    ) then
      raise exception 'Invalid or inactive branch for this organization';
    end if;
    return new;
  end if;

  select a.branch_id into v_branch_id
  from public.membership_branch_assignments a
  join public.organization_branches b
    on b.id = a.branch_id and b.organization_id = a.organization_id
  where a.organization_id = new.organization_id
    and a.membership_id = new.membership_id
    and a.is_primary
    and b.is_active;

  if v_branch_id is null then
    select b.id into v_branch_id
    from public.organization_branches b
    where b.organization_id = new.organization_id
      and b.is_default and b.is_active;
  end if;

  if v_branch_id is null then
    raise exception 'No active default branch exists for this organization';
  end if;

  new.branch_id := v_branch_id;
  return new;
end;
$$;

drop trigger if exists trg_assign_default_financial_branch on public.financial_transactions;
create trigger trg_assign_default_financial_branch
before insert on public.financial_transactions
for each row execute function public.assign_default_financial_branch();

alter table public.organization_branches enable row level security;
alter table public.membership_branch_assignments enable row level security;

drop policy if exists organization_branches_member_read on public.organization_branches;
create policy organization_branches_member_read
on public.organization_branches for select to authenticated
using (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = organization_branches.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
  )
);

drop policy if exists organization_branches_manager_insert on public.organization_branches;
create policy organization_branches_manager_insert
on public.organization_branches for insert to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = organization_branches.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin', 'manager')
  )
);

drop policy if exists organization_branches_manager_update on public.organization_branches;
create policy organization_branches_manager_update
on public.organization_branches for update to authenticated
using (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = organization_branches.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin', 'manager')
  )
)
with check (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = organization_branches.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin', 'manager')
  )
);

drop policy if exists membership_branch_assignments_member_read on public.membership_branch_assignments;
create policy membership_branch_assignments_member_read
on public.membership_branch_assignments for select to authenticated
using (
  exists (
    select 1 from public.committee_memberships target
    where target.id = membership_branch_assignments.membership_id
      and target.organization_id = membership_branch_assignments.organization_id
      and target.user_id = (select auth.uid())
  )
  or exists (
    select 1 from public.committee_memberships actor
    where actor.organization_id = membership_branch_assignments.organization_id
      and actor.user_id = (select auth.uid())
      and actor.is_active
      and actor.role in ('committee_admin', 'manager')
  )
);

drop policy if exists membership_branch_assignments_manager_insert on public.membership_branch_assignments;
create policy membership_branch_assignments_manager_insert
on public.membership_branch_assignments for insert to authenticated
with check (
  assigned_by = (select auth.uid())
  and exists (
    select 1 from public.committee_memberships actor
    where actor.organization_id = membership_branch_assignments.organization_id
      and actor.user_id = (select auth.uid())
      and actor.is_active
      and actor.role in ('committee_admin', 'manager')
  )
);

drop policy if exists membership_branch_assignments_manager_update on public.membership_branch_assignments;
create policy membership_branch_assignments_manager_update
on public.membership_branch_assignments for update to authenticated
using (
  exists (
    select 1 from public.committee_memberships actor
    where actor.organization_id = membership_branch_assignments.organization_id
      and actor.user_id = (select auth.uid())
      and actor.is_active
      and actor.role in ('committee_admin', 'manager')
  )
)
with check (
  exists (
    select 1 from public.committee_memberships actor
    where actor.organization_id = membership_branch_assignments.organization_id
      and actor.user_id = (select auth.uid())
      and actor.is_active
      and actor.role in ('committee_admin', 'manager')
  )
);

drop policy if exists membership_branch_assignments_manager_delete on public.membership_branch_assignments;
create policy membership_branch_assignments_manager_delete
on public.membership_branch_assignments for delete to authenticated
using (
  exists (
    select 1 from public.committee_memberships actor
    where actor.organization_id = membership_branch_assignments.organization_id
      and actor.user_id = (select auth.uid())
      and actor.is_active
      and actor.role in ('committee_admin', 'manager')
  )
);

grant select, insert, update on public.organization_branches to authenticated;
grant select, insert, update, delete on public.membership_branch_assignments to authenticated;

-- Enforce branch membership consistency and provide an atomic primary-branch reassignment API.
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
    if new.membership_id is not null and not exists (
      select 1 from public.membership_branch_assignments a
      join public.organization_branches b
        on b.id = a.branch_id and b.organization_id = a.organization_id
      where a.organization_id = new.organization_id
        and a.membership_id = new.membership_id
        and a.branch_id = new.branch_id
        and b.is_active
    ) then
      raise exception 'Member is not assigned to the selected branch';
    end if;
    return new;
  end if;

  if new.membership_id is not null then
    select a.branch_id into v_branch_id
    from public.membership_branch_assignments a
    join public.organization_branches b
      on b.id = a.branch_id and b.organization_id = a.organization_id
    where a.organization_id = new.organization_id
      and a.membership_id = new.membership_id
      and a.is_primary and b.is_active;
  end if;

  if v_branch_id is null then
    select b.id into v_branch_id
    from public.organization_branches b
    where b.organization_id = new.organization_id
      and b.is_default and b.is_active;
  end if;

  if v_branch_id is null then
    raise exception 'No active default branch exists for this organization';
  end if;

  if new.membership_id is not null and not exists (
    select 1 from public.membership_branch_assignments a
    where a.organization_id = new.organization_id
      and a.membership_id = new.membership_id
      and a.branch_id = v_branch_id
  ) then
    raise exception 'Member has no assignment to the resolved branch';
  end if;

  new.branch_id := v_branch_id;
  return new;
end;
$$;

create or replace function public.set_member_primary_branch(
  p_organization_id uuid,
  p_membership_id uuid,
  p_branch_id uuid
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_actor_role text;
begin
  select cm.role into v_actor_role
  from public.committee_memberships cm
  where cm.organization_id = p_organization_id
    and cm.user_id = (select auth.uid())
    and cm.is_active
  limit 1;

  if v_actor_role not in ('committee_admin', 'manager') or v_actor_role is null then
    raise exception 'Only committee admins or managers can change branch assignments';
  end if;

  if not exists (
    select 1
    from public.committee_memberships target
    join public.organization_branches b
      on b.organization_id = target.organization_id
    where target.organization_id = p_organization_id
      and target.id = p_membership_id
      and target.is_active
      and b.id = p_branch_id
      and b.is_active
  ) then
    raise exception 'Active member and branch in the same organization are required';
  end if;

  update public.membership_branch_assignments
  set is_primary = false
  where organization_id = p_organization_id
    and membership_id = p_membership_id
    and is_primary;

  insert into public.membership_branch_assignments
    (organization_id, membership_id, branch_id, is_primary, assigned_by)
  values
    (p_organization_id, p_membership_id, p_branch_id, true, (select auth.uid()))
  on conflict (membership_id, branch_id)
  do update set is_primary = true, assigned_by = (select auth.uid());
end;
$$;

revoke all on function public.set_member_primary_branch(uuid, uuid, uuid) from public;
revoke all on function public.set_member_primary_branch(uuid, uuid, uuid) from anon;
grant execute on function public.set_member_primary_branch(uuid, uuid, uuid) to authenticated;
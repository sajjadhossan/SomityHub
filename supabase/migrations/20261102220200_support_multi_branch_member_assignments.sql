create or replace function public.set_member_branch_assignments(
  p_organization_id uuid,
  p_membership_id uuid,
  p_branch_ids uuid[],
  p_primary_branch_id uuid
) returns void
language plpgsql security definer set search_path = '' as $$
declare v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if not exists(select 1 from public.committee_memberships cm where cm.organization_id=p_organization_id and cm.user_id=v_actor and cm.is_active and cm.role in ('committee_admin','manager')) then
    raise exception 'Only committee admins or managers can manage branch assignments';
  end if;
  if not exists(select 1 from public.committee_memberships cm where cm.organization_id=p_organization_id and cm.id=p_membership_id and cm.is_active) then
    raise exception 'Active member not found';
  end if;
  if coalesce(cardinality(p_branch_ids),0)=0 or p_primary_branch_id is null or not (p_primary_branch_id=any(p_branch_ids)) then
    raise exception 'At least one branch and a selected primary branch are required';
  end if;
  if exists(
    select 1 from unnest(p_branch_ids) requested(id)
    left join public.organization_branches b on b.id=requested.id and b.organization_id=p_organization_id and b.is_active
    where b.id is null
  ) then raise exception 'All selected branches must be active and belong to this organization'; end if;
  delete from public.membership_branch_assignments a
  where a.organization_id=p_organization_id and a.membership_id=p_membership_id
    and not (a.branch_id=any(p_branch_ids));
  insert into public.membership_branch_assignments(organization_id,membership_id,branch_id,is_primary,assigned_by)
  select p_organization_id,p_membership_id,branch_id,branch_id=p_primary_branch_id,v_actor
  from (select distinct unnest(p_branch_ids) as branch_id) selected
  on conflict(membership_id,branch_id) do update
    set is_primary=excluded.is_primary,assigned_by=excluded.assigned_by;
end $$;
revoke all on function public.set_member_branch_assignments(uuid,uuid,uuid[],uuid) from public,anon;
grant execute on function public.set_member_branch_assignments(uuid,uuid,uuid[],uuid) to authenticated;

create or replace function public.prevent_deactivate_assigned_branch()
returns trigger language plpgsql set search_path = '' as $$
begin
  if old.is_active and not new.is_active and exists(
    select 1 from public.membership_branch_assignments a
    where a.organization_id=old.organization_id and a.branch_id=old.id
  ) then
    raise exception 'Cannot deactivate a branch while members are assigned to it';
  end if;
  return new;
end $$;
drop trigger if exists trg_prevent_deactivate_assigned_branch on public.organization_branches;
create trigger trg_prevent_deactivate_assigned_branch
before update of is_active on public.organization_branches
for each row execute function public.prevent_deactivate_assigned_branch();
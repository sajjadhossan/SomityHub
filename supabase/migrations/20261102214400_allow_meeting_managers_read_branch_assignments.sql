drop policy if exists membership_branch_assignments_operations_read on public.membership_branch_assignments;
create policy membership_branch_assignments_operations_read
on public.membership_branch_assignments for select to authenticated
using (
  exists (
    select 1 from public.committee_memberships actor
    where actor.organization_id = membership_branch_assignments.organization_id
      and actor.user_id = (select auth.uid())
      and actor.is_active
      and actor.role in ('committee_admin','manager','general_secretary','secretary')
  )
);
-- Preserve meeting-branch membership integrity when attendance rows are edited.
drop policy if exists cooperative_attendance_manager_update on public.cooperative_attendance;
create policy cooperative_attendance_manager_update on public.cooperative_attendance
for update to authenticated
using (
 exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_attendance.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','general_secretary','secretary'))
)
with check (
 exists(select 1 from public.committee_memberships cm where cm.organization_id=cooperative_attendance.organization_id and cm.user_id=(select auth.uid()) and cm.is_active and cm.role in ('committee_admin','manager','general_secretary','secretary'))
 and exists(
  select 1 from public.cooperative_meetings m
  join public.membership_branch_assignments a on a.organization_id=m.organization_id and a.membership_id=cooperative_attendance.membership_id and a.branch_id=m.branch_id
  where m.id=cooperative_attendance.meeting_id and m.organization_id=cooperative_attendance.organization_id
 )
);
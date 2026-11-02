-- Add a restrictive policy so all existing permissive attendance update policies
-- must also satisfy the meeting-branch membership assignment check.
create policy cooperative_attendance_branch_integrity_update
on public.cooperative_attendance as restrictive
for update to authenticated
using (
 exists(select 1 from public.cooperative_meetings m
 join public.membership_branch_assignments a on a.organization_id=m.organization_id and a.membership_id=cooperative_attendance.membership_id and a.branch_id=m.branch_id
 where m.id=cooperative_attendance.meeting_id and m.organization_id=cooperative_attendance.organization_id)
)
with check (
 exists(select 1 from public.cooperative_meetings m
 join public.membership_branch_assignments a on a.organization_id=m.organization_id and a.membership_id=cooperative_attendance.membership_id and a.branch_id=m.branch_id
 where m.id=cooperative_attendance.meeting_id and m.organization_id=cooperative_attendance.organization_id)
);
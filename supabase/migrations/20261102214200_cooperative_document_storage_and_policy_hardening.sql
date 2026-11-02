-- Private document storage and tightened cooperative-operation write boundaries.
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'cooperative-documents',
  'cooperative-documents',
  false,
  20971520,
  array['application/pdf','image/jpeg','image/png','image/webp','application/msword','application/vnd.openxmlformats-officedocument.wordprocessingml.document','application/vnd.ms-excel','application/vnd.openxmlformats-officedocument.spreadsheetml.sheet']
)
on conflict (id) do update
set public = false,
    file_size_limit = excluded.file_size_limit,
    allowed_mime_types = excluded.allowed_mime_types;

-- Storage paths are organization_id/uploader_id/filename.
create policy cooperative_documents_storage_upload
on storage.objects for insert to authenticated
with check (
  bucket_id = 'cooperative-documents'
  and (storage.foldername(name))[1] is not null
  and (storage.foldername(name))[2] = (select auth.uid())::text
  and exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = ((storage.foldername(name))[1])::uuid
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager')
  )
);

create policy cooperative_documents_storage_read
on storage.objects for select to authenticated
using (
  bucket_id = 'cooperative-documents'
  and exists (
    select 1 from public.cooperative_documents d
    join public.committee_memberships cm
      on cm.organization_id = d.organization_id
     and cm.user_id = (select auth.uid())
     and cm.is_active
    where d.storage_path = storage.objects.name
      and d.organization_id = ((storage.foldername(storage.objects.name))[1])::uuid
      and (d.visibility = 'committee' or cm.role in ('committee_admin','manager','secretary','general_secretary','auditor'))
  )
);

-- Restrict attendance records to members assigned to the meeting's branch.
drop policy if exists cooperative_attendance_manager_write on public.cooperative_attendance;
create policy cooperative_attendance_manager_insert
on public.cooperative_attendance for insert to authenticated
with check (
  marked_by = (select auth.uid())
  and exists (
    select 1
    from public.cooperative_meetings m
    join public.committee_memberships actor
      on actor.organization_id = m.organization_id
     and actor.user_id = (select auth.uid())
     and actor.is_active
     and actor.role in ('committee_admin','manager','general_secretary','secretary')
    join public.membership_branch_assignments a
      on a.organization_id = m.organization_id
     and a.membership_id = cooperative_attendance.membership_id
     and a.branch_id = m.branch_id
    where m.id = cooperative_attendance.meeting_id
      and m.organization_id = cooperative_attendance.organization_id
  )
);
create policy cooperative_attendance_manager_update
on public.cooperative_attendance for update to authenticated
using (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = cooperative_attendance.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager','general_secretary','secretary')
  )
)
with check (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = cooperative_attendance.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager','general_secretary','secretary')
  )
);
create policy cooperative_attendance_manager_delete
on public.cooperative_attendance for delete to authenticated
using (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = cooperative_attendance.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager','general_secretary','secretary')
  )
);

-- Meeting authorship is immutable; managers may update/delete meetings without rewriting created_by.
drop policy if exists cooperative_meetings_manager_write on public.cooperative_meetings;
create policy cooperative_meetings_manager_insert
on public.cooperative_meetings for insert to authenticated
with check (
  created_by = (select auth.uid())
  and exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = cooperative_meetings.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager','general_secretary','secretary')
  )
);
create policy cooperative_meetings_manager_update
on public.cooperative_meetings for update to authenticated
using (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = cooperative_meetings.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager','general_secretary','secretary')
  )
)
with check (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = cooperative_meetings.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager','general_secretary','secretary')
  )
);
create policy cooperative_meetings_manager_delete
on public.cooperative_meetings for delete to authenticated
using (
  exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = cooperative_meetings.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and cm.role in ('committee_admin','manager','general_secretary','secretary')
  )
);
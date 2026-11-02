-- Membership lifecycle, private member photos, and QR verification history.
ALTER TABLE public.committee_memberships ADD COLUMN IF NOT EXISTS status text;
UPDATE public.committee_memberships
SET status = CASE WHEN is_active THEN 'active' ELSE 'suspended' END
WHERE status IS NULL;
ALTER TABLE public.committee_memberships
  ALTER COLUMN status SET DEFAULT 'active',
  ALTER COLUMN status SET NOT NULL;
ALTER TABLE public.committee_memberships
  DROP CONSTRAINT IF EXISTS committee_memberships_status_check;
ALTER TABLE public.committee_memberships
  ADD CONSTRAINT committee_memberships_status_check
  CHECK (status IN ('active', 'pending', 'suspended', 'expired'));

ALTER TABLE public.member_details ADD COLUMN IF NOT EXISTS photo_path text;

CREATE OR REPLACE FUNCTION public.admin_update_committee_member_status(
  p_organization_id uuid, p_membership_id uuid, p_new_status text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_target public.committee_memberships%ROWTYPE;
  v_admin_count integer;
BEGIN
  IF v_actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
  IF p_new_status IS NULL OR p_new_status NOT IN ('active','pending','suspended','expired') THEN
    RAISE EXCEPTION 'Invalid membership status';
  END IF;
  PERFORM 1 FROM public.organizations WHERE id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Committee not found'; END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.committee_memberships cm
    WHERE cm.organization_id = p_organization_id AND cm.user_id = v_actor
      AND cm.is_active AND cm.role IN ('committee_admin','manager')
  ) THEN RAISE EXCEPTION 'Only an active Committee Admin or Manager can change membership status'; END IF;
  SELECT cm.* INTO v_target FROM public.committee_memberships cm
  WHERE cm.id = p_membership_id AND cm.organization_id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'Target membership not found in this committee'; END IF;
  IF v_target.user_id = v_actor THEN RAISE EXCEPTION 'You cannot change your own membership status'; END IF;
  IF v_target.status = p_new_status THEN RAISE EXCEPTION 'Member already has this status'; END IF;
  IF v_target.is_active AND v_target.role = 'committee_admin' AND p_new_status <> 'active' THEN
    SELECT count(*) INTO v_admin_count FROM public.committee_memberships cm
    WHERE cm.organization_id = p_organization_id AND cm.is_active
      AND cm.role = 'committee_admin' AND cm.id <> p_membership_id;
    IF v_admin_count < 1 THEN RAISE EXCEPTION 'The committee must retain at least one active Admin'; END IF;
  END IF;
  UPDATE public.committee_memberships
  SET status = p_new_status, is_active = (p_new_status = 'active')
  WHERE id = p_membership_id AND organization_id = p_organization_id;
  INSERT INTO public.audit_log (organization_id, actor_id, action, entity_type, entity_id, before_data, after_data)
  VALUES (p_organization_id, v_actor, 'committee_member_status_updated', 'committee_membership',
    p_membership_id,
    jsonb_build_object('membership_id',p_membership_id,'user_id',v_target.user_id,'status',v_target.status,'is_active',v_target.is_active),
    jsonb_build_object('membership_id',p_membership_id,'user_id',v_target.user_id,'status',p_new_status,'is_active',(p_new_status='active'),'changed_by',v_actor));
  INSERT INTO public.backup_outbox (organization_id,event_type,payload)
  VALUES (p_organization_id,'committee_member_status_updated',
    jsonb_build_object('membership_id',p_membership_id,'user_id',v_target.user_id,
      'old_status',v_target.status,'new_status',p_new_status,'changed_by',v_actor,'changed_at',now()));
  RETURN p_membership_id;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_update_committee_member_status(uuid,uuid,text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_committee_member_status(uuid,uuid,text) TO authenticated;

INSERT INTO storage.buckets (id,name,public,file_size_limit,allowed_mime_types)
VALUES ('member-photos','member-photos',FALSE,2097152,ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET public=FALSE,file_size_limit=EXCLUDED.file_size_limit,allowed_mime_types=EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS member_photo_committee_read ON storage.objects;
CREATE POLICY member_photo_committee_read ON storage.objects FOR SELECT TO authenticated
USING (bucket_id='member-photos' AND public.is_committee_member(((storage.foldername(name))[1])::uuid));

DROP POLICY IF EXISTS member_photo_manager_insert ON storage.objects;
CREATE POLICY member_photo_manager_insert ON storage.objects FOR INSERT TO authenticated
WITH CHECK (bucket_id='member-photos' AND EXISTS (
  SELECT 1 FROM public.committee_memberships actor
  JOIN public.committee_memberships target ON target.organization_id=actor.organization_id
  WHERE actor.organization_id::text=(storage.foldername(name))[1]
    AND target.id::text=(storage.foldername(name))[2]
    AND actor.user_id=(SELECT auth.uid()) AND actor.is_active
    AND actor.role IN ('committee_admin','manager')
));

DROP POLICY IF EXISTS member_photo_manager_update ON storage.objects;
CREATE POLICY member_photo_manager_update ON storage.objects FOR UPDATE TO authenticated
USING (bucket_id='member-photos' AND EXISTS (
  SELECT 1 FROM public.committee_memberships actor
  JOIN public.committee_memberships target ON target.organization_id=actor.organization_id
  WHERE actor.organization_id::text=(storage.foldername(name))[1]
    AND target.id::text=(storage.foldername(name))[2]
    AND actor.user_id=(SELECT auth.uid()) AND actor.is_active
    AND actor.role IN ('committee_admin','manager')
))
WITH CHECK (bucket_id='member-photos' AND EXISTS (
  SELECT 1 FROM public.committee_memberships actor
  JOIN public.committee_memberships target ON target.organization_id=actor.organization_id
  WHERE actor.organization_id::text=(storage.foldername(name))[1]
    AND target.id::text=(storage.foldername(name))[2]
    AND actor.user_id=(SELECT auth.uid()) AND actor.is_active
    AND actor.role IN ('committee_admin','manager')
));

DROP POLICY IF EXISTS member_photo_manager_delete ON storage.objects;
CREATE POLICY member_photo_manager_delete ON storage.objects FOR DELETE TO authenticated
USING (bucket_id='member-photos' AND EXISTS (
  SELECT 1 FROM public.committee_memberships actor
  JOIN public.committee_memberships target ON target.organization_id=actor.organization_id
  WHERE actor.organization_id::text=(storage.foldername(name))[1]
    AND target.id::text=(storage.foldername(name))[2]
    AND actor.user_id=(SELECT auth.uid()) AND actor.is_active
    AND actor.role IN ('committee_admin','manager')
));

CREATE TABLE IF NOT EXISTS public.qr_verification_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  organization_id uuid NOT NULL,
  membership_id uuid NOT NULL,
  scanned_by_membership_id uuid NOT NULL,
  scanned_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT qr_verification_logs_member_fk FOREIGN KEY (organization_id,membership_id)
    REFERENCES public.committee_memberships (organization_id,id),
  CONSTRAINT qr_verification_logs_scanner_fk FOREIGN KEY (organization_id,scanned_by_membership_id)
    REFERENCES public.committee_memberships (organization_id,id)
);
CREATE INDEX IF NOT EXISTS qr_verification_logs_org_scanned_at_idx
  ON public.qr_verification_logs (organization_id,scanned_at DESC);
CREATE INDEX IF NOT EXISTS qr_verification_logs_scanner_scanned_at_idx
  ON public.qr_verification_logs (scanned_by_membership_id,scanned_at DESC);
ALTER TABLE public.qr_verification_logs ENABLE ROW LEVEL SECURITY;
GRANT SELECT,INSERT ON public.qr_verification_logs TO authenticated;

DROP POLICY IF EXISTS qr_verification_logs_insert_active_scanner ON public.qr_verification_logs;
CREATE POLICY qr_verification_logs_insert_active_scanner ON public.qr_verification_logs
FOR INSERT TO authenticated WITH CHECK (EXISTS (
  SELECT 1 FROM public.committee_memberships scanner
  WHERE scanner.id=qr_verification_logs.scanned_by_membership_id
    AND scanner.organization_id=qr_verification_logs.organization_id
    AND scanner.user_id=(SELECT auth.uid()) AND scanner.is_active AND scanner.status='active'
));

DROP POLICY IF EXISTS qr_verification_logs_read_own_or_manager ON public.qr_verification_logs;
CREATE POLICY qr_verification_logs_read_own_or_manager ON public.qr_verification_logs
FOR SELECT TO authenticated USING (
  EXISTS (SELECT 1 FROM public.committee_memberships scanner
    WHERE scanner.id=scanned_by_membership_id AND scanner.user_id=(SELECT auth.uid()))
  OR EXISTS (SELECT 1 FROM public.committee_memberships manager
    WHERE manager.organization_id=qr_verification_logs.organization_id
      AND manager.user_id=(SELECT auth.uid()) AND manager.is_active
      AND manager.role IN ('committee_admin','manager'))
);

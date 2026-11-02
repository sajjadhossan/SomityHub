DROP POLICY IF EXISTS qr_verification_logs_insert_active_scanner ON public.qr_verification_logs;
CREATE POLICY qr_verification_logs_insert_active_scanner ON public.qr_verification_logs
FOR INSERT TO authenticated WITH CHECK (EXISTS (
  SELECT 1 FROM public.committee_memberships scanner
  WHERE scanner.id=qr_verification_logs.scanned_by_membership_id
    AND scanner.organization_id=qr_verification_logs.organization_id
    AND scanner.user_id=(SELECT auth.uid()) AND scanner.is_active AND scanner.status='active'
));

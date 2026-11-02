GRANT SELECT ON public.audit_log TO authenticated;

DROP POLICY IF EXISTS audit_committee_profile_history ON public.audit_log;
CREATE POLICY audit_committee_profile_history
  ON public.audit_log
  FOR SELECT TO authenticated
  USING (
    action = 'committee_profile_updated'
    AND organization_id IS NOT NULL
    AND public.is_committee_member(organization_id)
  );

-- Committee profile editing with admin-only access, immutable version increments,
-- audit history, and a public-read / admin-write logo bucket.

ALTER TABLE public.organizations
  ADD COLUMN IF NOT EXISTS logo_path text,
  ADD COLUMN IF NOT EXISTS version integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS updated_at timestamptz NOT NULL DEFAULT now();

REVOKE UPDATE ON public.organizations FROM authenticated;
GRANT UPDATE (name, logo_path) ON public.organizations TO authenticated;

DROP POLICY IF EXISTS organizations_update_committee_admin ON public.organizations;
CREATE POLICY organizations_update_committee_admin
  ON public.organizations
  FOR UPDATE TO authenticated
  USING (EXISTS (
    SELECT 1 FROM public.committee_memberships cm
    WHERE cm.organization_id = organizations.id
      AND cm.user_id = (SELECT auth.uid())
      AND cm.role = 'committee_admin'
      AND cm.is_active = TRUE
  ))
  WITH CHECK (EXISTS (
    SELECT 1 FROM public.committee_memberships cm
    WHERE cm.organization_id = organizations.id
      AND cm.user_id = (SELECT auth.uid())
      AND cm.role = 'committee_admin'
      AND cm.is_active = TRUE
  ));

CREATE SCHEMA IF NOT EXISTS private;
REVOKE ALL ON SCHEMA private FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION private.track_organization_profile_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name OR NEW.logo_path IS DISTINCT FROM OLD.logo_path THEN
    NEW.version := OLD.version + 1;
    NEW.updated_at := now();
  ELSE
    NEW.version := OLD.version;
    NEW.updated_at := OLD.updated_at;
  END IF;
  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION private.audit_organization_profile_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
BEGIN
  IF NEW.name IS DISTINCT FROM OLD.name OR NEW.logo_path IS DISTINCT FROM OLD.logo_path THEN
    INSERT INTO public.audit_log (organization_id, actor_id, action, entity_type, entity_id, before_data, after_data)
    VALUES (
      NEW.id,
      (SELECT auth.uid()),
      'committee_profile_updated',
      'organization',
      NEW.id,
      jsonb_build_object('name', OLD.name, 'logo_path', OLD.logo_path, 'version', OLD.version),
      jsonb_build_object('name', NEW.name, 'logo_path', NEW.logo_path, 'version', NEW.version)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS organizations_profile_version ON public.organizations;
CREATE TRIGGER organizations_profile_version
  BEFORE UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION private.track_organization_profile_version();
DROP TRIGGER IF EXISTS organizations_profile_audit ON public.organizations;
CREATE TRIGGER organizations_profile_audit
  AFTER UPDATE ON public.organizations
  FOR EACH ROW EXECUTE FUNCTION private.audit_organization_profile_change();

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('committee-logos', 'committee-logos', TRUE, 2097152, ARRAY['image/jpeg','image/png','image/webp'])
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

DROP POLICY IF EXISTS committee_logo_admin_upload ON storage.objects;
CREATE POLICY committee_logo_admin_upload
  ON storage.objects FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'committee-logos'
    AND EXISTS (
      SELECT 1 FROM public.committee_memberships cm
      WHERE cm.organization_id::text = (storage.foldername(name))[1]
        AND cm.user_id = (SELECT auth.uid())
        AND cm.role = 'committee_admin'
        AND cm.is_active = TRUE
    )
  );

DROP POLICY IF EXISTS committee_logo_admin_delete ON storage.objects;
CREATE POLICY committee_logo_admin_delete
  ON storage.objects FOR DELETE TO authenticated
  USING (
    bucket_id = 'committee-logos'
    AND EXISTS (
      SELECT 1 FROM public.committee_memberships cm
      WHERE cm.organization_id::text = (storage.foldername(name))[1]
        AND cm.user_id = (SELECT auth.uid())
        AND cm.role = 'committee_admin'
        AND cm.is_active = TRUE
    )
  );

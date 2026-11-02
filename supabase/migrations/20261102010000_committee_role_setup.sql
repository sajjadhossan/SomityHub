-- Committee roles are scoped to one committee. The creator receives the first
-- active Admin membership in create_committee; this migration expands how
-- registered accounts can be added and assigned a role.

ALTER TABLE public.committee_memberships
  DROP CONSTRAINT committee_memberships_role_check;

ALTER TABLE public.committee_memberships
  ADD CONSTRAINT committee_memberships_role_check CHECK (role IN (
    'committee_admin', 'manager', 'president', 'general_secretary',
    'assistant_secretary', 'accountant', 'treasurer', 'secretary',
    'auditor', 'member'
  ));

CREATE OR REPLACE FUNCTION public.is_committee_member(p_org_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM public.committee_memberships cm
    WHERE cm.organization_id = p_org_id
      AND cm.user_id = (SELECT auth.uid())
      AND cm.is_active = TRUE
  );
$$;

REVOKE ALL ON FUNCTION public.is_committee_member(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.is_committee_member(uuid) TO authenticated;

DROP POLICY IF EXISTS memberships_select_manager ON public.committee_memberships;
DROP POLICY IF EXISTS memberships_select_own ON public.committee_memberships;
DROP POLICY IF EXISTS memberships_select_committee_members ON public.committee_memberships;
CREATE POLICY memberships_select_committee_members
  ON public.committee_memberships
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()) OR public.is_committee_member(organization_id));

DROP POLICY IF EXISTS profiles_select_own ON public.profiles;
DROP POLICY IF EXISTS profiles_select_committee_members
  ON public.profiles;
CREATE POLICY profiles_select_committee_members
  ON public.profiles
  FOR SELECT TO authenticated
  USING (
    id = (SELECT auth.uid()) OR EXISTS (
      SELECT 1
      FROM public.committee_memberships cm
      WHERE cm.user_id = profiles.id
        AND public.is_committee_member(cm.organization_id)
    )
  );

CREATE OR REPLACE FUNCTION public.add_committee_member_by_email(
  p_organization_id uuid,
  p_email text,
  p_role text DEFAULT 'member',
  p_phone text DEFAULT NULL,
  p_address text DEFAULT NULL
)
RETURNS TABLE(membership_id uuid, member_code text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_user_id uuid;
  v_membership_id uuid := gen_random_uuid();
  v_member_code text;
  v_is_admin boolean;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_organization_id IS NULL OR NULLIF(trim(p_email), '') IS NULL THEN
    RAISE EXCEPTION 'Committee and account email are required';
  END IF;
  IF p_role IS NULL OR p_role NOT IN (
    'committee_admin', 'manager', 'president', 'general_secretary',
    'assistant_secretary', 'accountant', 'treasurer', 'secretary',
    'auditor', 'member'
  ) THEN
    RAISE EXCEPTION 'Invalid committee role';
  END IF;

  PERFORM 1 FROM public.organizations o
  WHERE o.id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Committee not found';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM public.committee_memberships cm
    WHERE cm.organization_id = p_organization_id
      AND cm.user_id = v_actor AND cm.is_active
      AND cm.role = 'committee_admin'
  ) INTO v_is_admin;

  IF NOT v_is_admin AND NOT public.is_committee_manager(p_organization_id) THEN
    RAISE EXCEPTION 'Only an active Committee Admin or Manager can add members';
  END IF;
  IF NOT v_is_admin AND p_role <> 'member' THEN
    RAISE EXCEPTION 'Only an active Committee Admin can assign committee roles';
  END IF;

  SELECT u.id INTO v_user_id
  FROM auth.users u
  WHERE lower(u.email) = lower(trim(p_email))
  LIMIT 1;
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'No registered account found for this email';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.profiles p WHERE p.id = v_user_id) THEN
    RAISE EXCEPTION 'The registered account profile is not ready yet';
  END IF;
  IF EXISTS (
    SELECT 1 FROM public.committee_memberships cm
    WHERE cm.organization_id = p_organization_id AND cm.user_id = v_user_id
  ) THEN
    RAISE EXCEPTION 'This account is already in the committee';
  END IF;

  v_member_code := 'MBR-' || upper(substr(replace(v_membership_id::text, '-', ''), 1, 8));
  INSERT INTO public.committee_memberships (
    id, organization_id, user_id, role, member_code, is_active
  ) VALUES (
    v_membership_id, p_organization_id, v_user_id, p_role, v_member_code, TRUE
  );

  INSERT INTO public.member_details (organization_id, membership_id, phone, address)
  VALUES (
    p_organization_id, v_membership_id,
    NULLIF(trim(p_phone), ''), NULLIF(trim(p_address), '')
  );

  INSERT INTO public.audit_log (
    organization_id, actor_id, action, entity_type, entity_id,
    before_data, after_data
  ) VALUES (
    p_organization_id, v_actor, 'committee_member_added',
    'committee_membership', v_membership_id, NULL,
    jsonb_build_object('user_id', v_user_id, 'role', p_role, 'email', lower(trim(p_email)))
  );

  INSERT INTO public.backup_outbox (organization_id, event_type, payload)
  VALUES (
    p_organization_id, 'committee_member_added',
    jsonb_build_object('membership_id', v_membership_id, 'user_id', v_user_id,
      'role', p_role, 'added_by', v_actor, 'added_at', now())
  );

  RETURN QUERY SELECT v_membership_id, v_member_code;
END;
$$;

REVOKE ALL ON FUNCTION public.add_committee_member_by_email(uuid, text, text, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.add_committee_member_by_email(uuid, text, text, text, text)
  TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_update_committee_member_role(
  p_organization_id uuid,
  p_membership_id uuid,
  p_new_role text
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_actor uuid := auth.uid();
  v_target public.committee_memberships%ROWTYPE;
  v_admin_count integer;
BEGIN
  IF v_actor IS NULL THEN
    RAISE EXCEPTION 'Authentication required';
  END IF;
  IF p_new_role IS NULL OR p_new_role NOT IN (
    'committee_admin', 'manager', 'president', 'general_secretary',
    'assistant_secretary', 'accountant', 'treasurer', 'secretary',
    'auditor', 'member'
  ) THEN
    RAISE EXCEPTION 'Invalid committee role';
  END IF;

  PERFORM 1 FROM public.organizations o
  WHERE o.id = p_organization_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Committee not found';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.committee_memberships cm
    WHERE cm.organization_id = p_organization_id
      AND cm.user_id = v_actor AND cm.is_active
      AND cm.role = 'committee_admin'
    FOR UPDATE
  ) THEN
    RAISE EXCEPTION 'Only an active Committee Admin can change member roles';
  END IF;

  SELECT cm.* INTO v_target
  FROM public.committee_memberships cm
  WHERE cm.id = p_membership_id AND cm.organization_id = p_organization_id
  FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Target membership not found in this committee';
  END IF;
  IF v_target.user_id = v_actor THEN
    RAISE EXCEPTION 'You cannot change your own committee role';
  END IF;
  IF v_target.role = p_new_role THEN
    RAISE EXCEPTION 'Member already has this role';
  END IF;

  IF v_target.is_active AND v_target.role = 'committee_admin'
     AND p_new_role <> 'committee_admin' THEN
    SELECT count(*) INTO v_admin_count
    FROM public.committee_memberships cm
    WHERE cm.organization_id = p_organization_id
      AND cm.is_active AND cm.role = 'committee_admin'
      AND cm.id <> p_membership_id;
    IF v_admin_count < 1 THEN
      RAISE EXCEPTION 'The committee must retain at least one active Admin';
    END IF;
  END IF;

  UPDATE public.committee_memberships
  SET role = p_new_role
  WHERE id = p_membership_id AND organization_id = p_organization_id;

  INSERT INTO public.audit_log (
    organization_id, actor_id, action, entity_type, entity_id, before_data, after_data
  ) VALUES (
    p_organization_id, v_actor, 'committee_member_role_updated',
    'committee_membership', p_membership_id,
    jsonb_build_object('membership_id', p_membership_id, 'user_id', v_target.user_id, 'role', v_target.role),
    jsonb_build_object('membership_id', p_membership_id, 'user_id', v_target.user_id,
      'role', p_new_role, 'changed_by', v_actor)
  );

  INSERT INTO public.backup_outbox (organization_id, event_type, payload)
  VALUES (
    p_organization_id, 'committee_member_role_updated',
    jsonb_build_object('membership_id', p_membership_id, 'user_id', v_target.user_id,
      'old_role', v_target.role, 'new_role', p_new_role, 'changed_by', v_actor, 'changed_at', now())
  );

  RETURN p_membership_id;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_committee_member_role(uuid, uuid, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_committee_member_role(uuid, uuid, text)
  TO authenticated;

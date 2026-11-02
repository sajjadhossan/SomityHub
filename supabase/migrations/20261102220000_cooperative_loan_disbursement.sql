create or replace function public.disburse_cooperative_loan(p_loan_id uuid)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_loan public.cooperative_loans%rowtype; v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_loan from public.cooperative_loans where id=p_loan_id for update;
  if not found or v_loan.status <> 'approved' then raise exception 'Only approved loans can be disbursed'; end if;
  if not exists(select 1 from public.committee_memberships cm where cm.organization_id=v_loan.organization_id and cm.user_id=v_actor and cm.is_active and cm.role in ('committee_admin','manager','treasurer')) then raise exception 'Not authorized to disburse loans'; end if;
  update public.cooperative_loans set status='disbursed',updated_at=now() where id=p_loan_id;
  insert into public.audit_log(organization_id,actor_id,action,entity_type,entity_id,after_data)
  values(v_loan.organization_id,v_actor,'cooperative_loan_disbursed','cooperative_loan',p_loan_id,jsonb_build_object('status','disbursed','principal_amount',v_loan.principal_amount,'branch_id',v_loan.branch_id));
  return p_loan_id;
end $$;
revoke all on function public.disburse_cooperative_loan(uuid) from public,anon;
grant execute on function public.disburse_cooperative_loan(uuid) to authenticated;

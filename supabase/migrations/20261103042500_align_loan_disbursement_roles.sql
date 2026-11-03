-- Preserve the existing separation-of-duties rule: accountants can record repayments,
-- but only committee admins, managers and treasurers can disburse or initialize schedules.
create or replace function public.disburse_cooperative_loan(
  p_loan_id uuid,
  p_reference_number text default null
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan public.cooperative_loans%rowtype;
  v_actor uuid := (select auth.uid());
  v_transaction_id uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  select * into v_loan from public.cooperative_loans where id=p_loan_id for update;
  if not found or v_loan.status <> 'approved' then raise exception 'Only approved loans can be disbursed'; end if;
  if not exists(select 1 from public.committee_memberships cm
    where cm.organization_id=v_loan.organization_id and cm.user_id=v_actor and cm.is_active
      and cm.role in ('committee_admin','manager','treasurer')) then
    raise exception 'Not authorized to disburse loans';
  end if;
  if v_loan.requested_by=v_actor then raise exception 'Loan requester cannot disburse own loan'; end if;
  update public.cooperative_loans
    set status='disbursed',disbursed_on=current_date,updated_at=now()
    where id=p_loan_id;
  perform public.create_cooperative_loan_installment_schedule(p_loan_id);
  insert into public.financial_transactions(
    organization_id,membership_id,branch_id,transaction_type,amount,description,
    reference_number,status,created_by,approved_by,approved_at
  ) values (
    v_loan.organization_id,v_loan.membership_id,v_loan.branch_id,'loan_disbursement',
    v_loan.principal_amount,'Cooperative loan disbursement',p_reference_number,
    'approved',v_actor,v_actor,now()
  ) returning id into v_transaction_id;
  insert into public.audit_log(organization_id,actor_id,action,entity_type,entity_id,after_data)
  values(v_loan.organization_id,v_actor,'cooperative_loan_disbursed','cooperative_loan',p_loan_id,
    jsonb_build_object('transaction_id',v_transaction_id,'amount',v_loan.principal_amount,
      'disbursed_on',current_date,'installment_count',v_loan.term_months));
  return v_transaction_id;
end;
$$;

create or replace function public.initialize_cooperative_loan_installment_schedule(
  p_loan_id uuid,
  p_disbursement_date date
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan public.cooperative_loans%rowtype;
  v_actor uuid := (select auth.uid());
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_disbursement_date is null or p_disbursement_date > current_date then
    raise exception 'A valid actual disbursement date is required';
  end if;
  select * into v_loan from public.cooperative_loans where id=p_loan_id for update;
  if not found or v_loan.status <> 'disbursed' then raise exception 'Only disbursed loans can be initialized'; end if;
  if not exists(select 1 from public.committee_memberships cm
    where cm.organization_id=v_loan.organization_id and cm.user_id=v_actor and cm.is_active
      and cm.role in ('committee_admin','manager','treasurer')) then
    raise exception 'Not authorized to initialize loan schedule';
  end if;
  if v_loan.disbursed_on is not null or exists(
    select 1 from public.cooperative_loan_installments where loan_id=p_loan_id
  ) then raise exception 'Loan schedule is already initialized'; end if;
  update public.cooperative_loans set disbursed_on=p_disbursement_date,updated_at=now() where id=p_loan_id;
  perform public.create_cooperative_loan_installment_schedule(p_loan_id);
  insert into public.audit_log(organization_id,actor_id,action,entity_type,entity_id,after_data)
  values(v_loan.organization_id,v_actor,'cooperative_loan_schedule_initialized','cooperative_loan',p_loan_id,
    jsonb_build_object('disbursed_on',p_disbursement_date,'installment_count',v_loan.term_months));
  return v_loan.term_months;
end;
$$;

revoke all on function public.disburse_cooperative_loan(uuid,text) from public,anon;
grant execute on function public.disburse_cooperative_loan(uuid,text) to authenticated;
revoke all on function public.initialize_cooperative_loan_installment_schedule(uuid,date) from public,anon;
grant execute on function public.initialize_cooperative_loan_installment_schedule(uuid,date) to authenticated;
notify pgrst, 'reload schema';

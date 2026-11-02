-- Authenticated, audited approval and repayment workflows for loans and vouchers.
create or replace function public.review_cooperative_loan(p_loan_id uuid,p_decision text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_loan public.cooperative_loans%rowtype; v_actor uuid;
begin
 v_actor := (select auth.uid());
 if v_actor is null then raise exception 'Authentication required'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into v_loan from public.cooperative_loans where id=p_loan_id for update;
 if not found or v_loan.status <> 'pending' then raise exception 'Pending loan request not found'; end if;
 if v_loan.requested_by=v_actor then raise exception 'Cannot review your own loan request'; end if;
 if not exists(select 1 from public.committee_memberships cm where cm.organization_id=v_loan.organization_id and cm.user_id=v_actor and cm.is_active and cm.role in ('committee_admin','manager','treasurer')) then raise exception 'Not authorized to review loans'; end if;
 update public.cooperative_loans set status=p_decision,reviewed_by=v_actor,reviewed_at=now(),updated_at=now() where id=p_loan_id;
 insert into public.audit_log(organization_id,actor_id,action,entity_type,entity_id,after_data)
 values(v_loan.organization_id,v_actor,'cooperative_loan_'||p_decision,'cooperative_loan',p_loan_id,jsonb_build_object('status',p_decision,'principal_amount',v_loan.principal_amount));
 return p_loan_id;
end $$;
create or replace function public.record_cooperative_loan_repayment(p_loan_id uuid,p_amount numeric,p_payment_date date,p_reference_number text default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_loan public.cooperative_loans%rowtype; v_actor uuid; v_paid numeric; v_id uuid;
begin
 v_actor := (select auth.uid());
 if v_actor is null then raise exception 'Authentication required'; end if;
 if p_amount is null or p_amount<=0 then raise exception 'Repayment amount must be positive'; end if;
 select * into v_loan from public.cooperative_loans where id=p_loan_id for update;
 if not found or v_loan.status not in ('approved','disbursed') then raise exception 'Loan is not open for repayment'; end if;
 if not exists(select 1 from public.committee_memberships cm where cm.organization_id=v_loan.organization_id and cm.user_id=v_actor and cm.is_active and cm.role in ('committee_admin','manager','treasurer','accountant')) then raise exception 'Not authorized to record repayment'; end if;
 select coalesce(sum(amount),0) into v_paid from public.cooperative_loan_repayments where organization_id=v_loan.organization_id and loan_id=p_loan_id;
 if v_paid+p_amount > v_loan.principal_amount*(1+v_loan.interest_rate/100) then raise exception 'Repayment exceeds outstanding loan amount'; end if;
 insert into public.cooperative_loan_repayments(organization_id,loan_id,amount,payment_date,reference_number,received_by)
 values(v_loan.organization_id,p_loan_id,p_amount,coalesce(p_payment_date,current_date),p_reference_number,v_actor) returning id into v_id;
 if v_paid+p_amount = v_loan.principal_amount*(1+v_loan.interest_rate/100) then update public.cooperative_loans set status='closed',updated_at=now() where id=p_loan_id; end if;
 insert into public.audit_log(organization_id,actor_id,action,entity_type,entity_id,after_data)
 values(v_loan.organization_id,v_actor,'cooperative_loan_repayment_recorded','cooperative_loan',p_loan_id,jsonb_build_object('repayment_id',v_id,'amount',p_amount,'total_paid',v_paid+p_amount));
 return v_id;
end $$;
create or replace function public.review_cooperative_voucher(p_voucher_id uuid,p_decision text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_row public.cooperative_vouchers%rowtype; v_actor uuid;
begin
 v_actor := (select auth.uid());
 if v_actor is null then raise exception 'Authentication required'; end if;
 if p_decision not in ('approved','rejected') then raise exception 'Invalid decision'; end if;
 select * into v_row from public.cooperative_vouchers where id=p_voucher_id for update;
 if not found or v_row.status <> 'pending' then raise exception 'Pending voucher not found'; end if;
 if v_row.created_by=v_actor then raise exception 'Cannot review your own voucher'; end if;
 if not exists(select 1 from public.committee_memberships cm where cm.organization_id=v_row.organization_id and cm.user_id=v_actor and cm.is_active and cm.role in ('committee_admin','manager','treasurer')) then raise exception 'Not authorized to review vouchers'; end if;
 update public.cooperative_vouchers set status=p_decision,approved_by=case when p_decision='approved' then v_actor else null end,approved_at=case when p_decision='approved' then now() else null end where id=p_voucher_id;
 insert into public.audit_log(organization_id,actor_id,action,entity_type,entity_id,after_data)
 values(v_row.organization_id,v_actor,'cooperative_voucher_'||p_decision,'cooperative_voucher',p_voucher_id,jsonb_build_object('status',p_decision,'amount',v_row.amount,'type',v_row.voucher_type));
 return p_voucher_id;
end $$;
revoke all on function public.review_cooperative_loan(uuid,text) from public,anon;
revoke all on function public.record_cooperative_loan_repayment(uuid,numeric,date,text) from public,anon;
revoke all on function public.review_cooperative_voucher(uuid,text) from public,anon;
grant execute on function public.review_cooperative_loan(uuid,text) to authenticated;
grant execute on function public.record_cooperative_loan_repayment(uuid,numeric,date,text) to authenticated;
grant execute on function public.review_cooperative_voucher(uuid,text) to authenticated;
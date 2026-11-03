-- Idempotent loan repayments: the same client request key can post at most once per organization.
alter table public.cooperative_loan_repayments
  add column if not exists idempotency_key uuid;

create unique index if not exists cooperative_loan_repayments_org_idempotency_key
  on public.cooperative_loan_repayments(organization_id, idempotency_key)
  where idempotency_key is not null;

create or replace function public.record_cooperative_loan_repayment(
  p_loan_id uuid,
  p_amount numeric,
  p_payment_date date,
  p_reference_number text,
  p_idempotency_key uuid
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan public.cooperative_loans%rowtype;
  v_actor uuid := (select auth.uid());
  v_paid numeric(14,2);
  v_total_due numeric(14,2);
  v_id uuid;
  v_transaction_id uuid;
  v_existing public.cooperative_loan_repayments%rowtype;
  v_amount numeric(14,2) := round(p_amount, 2);
  v_payment_date date := coalesce(p_payment_date, current_date);
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_idempotency_key is null then raise exception 'An idempotency key is required'; end if;
  if p_amount is null or p_amount <= 0 or v_amount <= 0 then
    raise exception 'Repayment amount must be positive';
  end if;

  select * into v_loan
  from public.cooperative_loans
  where id = p_loan_id
  for update;

  if not found then raise exception 'Loan not found'; end if;

  if not exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = v_loan.organization_id
      and cm.user_id = v_actor
      and cm.is_active
      and cm.role in ('committee_admin','manager','treasurer','accountant')
  ) then
    raise exception 'Not authorized to record repayment';
  end if;

  select * into v_existing
  from public.cooperative_loan_repayments
  where organization_id = v_loan.organization_id
    and idempotency_key = p_idempotency_key
  for update;

  if found then
    if v_existing.loan_id <> p_loan_id or v_existing.amount <> v_amount
       or v_existing.payment_date <> v_payment_date then
      raise exception 'Idempotency key was already used for a different repayment';
    end if;
    return v_existing.id;
  end if;

  if v_loan.status <> 'disbursed' then
    raise exception 'Loan must be disbursed before repayment';
  end if;

  v_total_due := round(v_loan.principal_amount * (1 + v_loan.interest_rate / 100), 2);

  select coalesce(sum(amount), 0) into v_paid
  from public.cooperative_loan_repayments
  where organization_id = v_loan.organization_id
    and loan_id = p_loan_id;

  if round(v_paid + v_amount, 2) > v_total_due then
    raise exception 'Repayment exceeds outstanding loan amount';
  end if;

  insert into public.cooperative_loan_repayments(
    organization_id, loan_id, amount, payment_date, reference_number,
    received_by, idempotency_key
  )
  values (
    v_loan.organization_id, p_loan_id, v_amount, v_payment_date,
    p_reference_number, v_actor, p_idempotency_key
  )
  returning id into v_id;

  if exists (
    select 1 from public.cooperative_loan_installments where loan_id = p_loan_id
  ) then
    perform public.allocate_cooperative_loan_installment_payment(p_loan_id, v_amount);
  end if;

  insert into public.financial_transactions(
    organization_id, membership_id, branch_id, transaction_type, amount,
    description, reference_number, status, created_by, approved_by,
    approved_at, idempotency_key
  )
  values (
    v_loan.organization_id, v_loan.membership_id, v_loan.branch_id,
    'loan_repayment', v_amount, 'Cooperative loan repayment',
    p_reference_number, 'approved', v_actor, v_actor, now(), p_idempotency_key
  )
  returning id into v_transaction_id;

  if round(v_paid + v_amount, 2) >= v_total_due then
    update public.cooperative_loans
    set status = 'closed', updated_at = now()
    where id = p_loan_id;
  end if;

  insert into public.audit_log(
    organization_id, actor_id, action, entity_type, entity_id, after_data
  )
  values (
    v_loan.organization_id, v_actor, 'cooperative_loan_repayment_recorded',
    'cooperative_loan', p_loan_id,
    jsonb_build_object(
      'repayment_id', v_id,
      'transaction_id', v_transaction_id,
      'amount', v_amount,
      'total_paid', round(v_paid + v_amount, 2),
      'idempotency_key', p_idempotency_key
    )
  );

  return v_id;
end;
$$;

revoke all on function public.record_cooperative_loan_repayment(uuid,numeric,date,text,uuid)
  from public, anon;
grant execute on function public.record_cooperative_loan_repayment(uuid,numeric,date,text,uuid)
  to authenticated;

-- Disable the pre-idempotency RPC signature so older clients cannot bypass request deduplication.
revoke all on function public.record_cooperative_loan_repayment(uuid,numeric,date,text)
  from public, anon, authenticated;

notify pgrst, 'reload schema';

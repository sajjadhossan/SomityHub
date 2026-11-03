-- Android loan installment schedules with role-checked lifecycle and atomic repayment allocation.
alter table public.cooperative_loans
  add column if not exists disbursed_on date;

create table if not exists public.cooperative_loan_installments (
  id uuid primary key default gen_random_uuid(),
  organization_id uuid not null,
  loan_id uuid not null,
  installment_no integer not null check (installment_no > 0),
  due_date date not null,
  amount numeric(14,2) not null check (amount > 0),
  paid_amount numeric(14,2) not null default 0 check (paid_amount >= 0 and paid_amount <= amount),
  created_at timestamptz not null default now(),
  constraint cooperative_loan_installments_loan_fk
    foreign key (organization_id, loan_id)
    references public.cooperative_loans(organization_id, id) on delete cascade,
  constraint cooperative_loan_installments_number_unique unique (loan_id, installment_no)
);

create index if not exists cooperative_loan_installments_org_due_idx
  on public.cooperative_loan_installments(organization_id, due_date, loan_id);

alter table public.cooperative_loan_installments enable row level security;

create policy cooperative_loan_installments_member_read
on public.cooperative_loan_installments
for select to authenticated
using (
  exists (
    select 1
    from public.cooperative_loans l
    join public.committee_memberships cm
      on cm.organization_id = l.organization_id
    where l.id = cooperative_loan_installments.loan_id
      and l.organization_id = cooperative_loan_installments.organization_id
      and cm.user_id = (select auth.uid())
      and cm.is_active
      and (
        cm.id = l.membership_id
        or cm.role in ('committee_admin','manager','treasurer','accountant','auditor')
      )
  )
);

grant select on public.cooperative_loan_installments to authenticated;

-- Internal allocator: distribute a payment to the oldest unpaid installments.
create or replace function public.allocate_cooperative_loan_installment_payment(
  p_loan_id uuid,
  p_amount numeric
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_remaining numeric(14,2) := round(p_amount, 2);
  v_installment record;
  v_allocation numeric(14,2);
begin
  for v_installment in
    select id, amount, paid_amount
    from public.cooperative_loan_installments
    where loan_id = p_loan_id
    order by installment_no
    for update
  loop
    exit when v_remaining <= 0;
    v_allocation := least(v_remaining, v_installment.amount - v_installment.paid_amount);
    if v_allocation > 0 then
      update public.cooperative_loan_installments
      set paid_amount = paid_amount + v_allocation
      where id = v_installment.id;
      v_remaining := v_remaining - v_allocation;
    end if;
  end loop;

  if v_remaining > 0 then
    raise exception 'Installment allocation exceeds scheduled loan amount';
  end if;
end;
$$;

revoke all on function public.allocate_cooperative_loan_installment_payment(uuid,numeric)
  from public, anon, authenticated;

-- Internal schedule builder. Existing repayments are replayed in payment-date order
-- when a legacy disbursed loan is initialized, preserving its historical paid balance.
create or replace function public.create_cooperative_loan_installment_schedule(p_loan_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_loan public.cooperative_loans%rowtype;
  v_total numeric(14,2);
  v_regular numeric(14,2);
  v_amount numeric(14,2);
  v_payment record;
  i integer;
begin
  select * into v_loan
  from public.cooperative_loans
  where id = p_loan_id
  for update;

  if not found or v_loan.status <> 'disbursed' or v_loan.disbursed_on is null then
    raise exception 'A disbursed loan with a confirmed disbursement date is required';
  end if;

  if exists (
    select 1 from public.cooperative_loan_installments
    where loan_id = p_loan_id
  ) then
    raise exception 'Installment schedule already exists';
  end if;

  v_total := round(v_loan.principal_amount * (1 + v_loan.interest_rate / 100), 2);
  v_regular := trunc(v_total / v_loan.term_months, 2);

  if v_regular < 0.01 then
    raise exception 'Total repayable amount is too small for the selected installment term';
  end if;

  for i in 1..v_loan.term_months loop
    v_amount := case
      when i = v_loan.term_months then v_total - (v_regular * (v_loan.term_months - 1))
      else v_regular
    end;

    insert into public.cooperative_loan_installments(
      organization_id, loan_id, installment_no, due_date, amount
    )
    values (
      v_loan.organization_id,
      v_loan.id,
      i,
      (v_loan.disbursed_on::timestamp + make_interval(months => i))::date,
      v_amount
    );
  end loop;

  for v_payment in
    select amount
    from public.cooperative_loan_repayments
    where organization_id = v_loan.organization_id
      and loan_id = v_loan.id
    order by payment_date, created_at, id
  loop
    perform public.allocate_cooperative_loan_installment_payment(v_loan.id, v_payment.amount);
  end loop;
end;
$$;

revoke all on function public.create_cooperative_loan_installment_schedule(uuid)
  from public, anon, authenticated;

-- New disbursements create the schedule in the same transaction as the cash-ledger posting.
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

  select * into v_loan
  from public.cooperative_loans
  where id = p_loan_id
  for update;

  if not found or v_loan.status <> 'approved' then
    raise exception 'Only approved loans can be disbursed';
  end if;

  if not exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = v_loan.organization_id
      and cm.user_id = v_actor
      and cm.is_active
      and cm.role in ('committee_admin','manager','treasurer','accountant')
  ) then
    raise exception 'Not authorized to disburse loans';
  end if;

  if v_loan.requested_by = v_actor then
    raise exception 'Loan requester cannot disburse own loan';
  end if;

  update public.cooperative_loans
  set status = 'disbursed', disbursed_on = current_date, updated_at = now()
  where id = p_loan_id;

  perform public.create_cooperative_loan_installment_schedule(p_loan_id);

  insert into public.financial_transactions(
    organization_id, membership_id, branch_id, transaction_type, amount,
    description, reference_number, status, created_by, approved_by, approved_at
  )
  values (
    v_loan.organization_id, v_loan.membership_id, v_loan.branch_id,
    'loan_disbursement', v_loan.principal_amount, 'Cooperative loan disbursement',
    p_reference_number, 'approved', v_actor, v_actor, now()
  )
  returning id into v_transaction_id;

  insert into public.audit_log(
    organization_id, actor_id, action, entity_type, entity_id, after_data
  )
  values (
    v_loan.organization_id, v_actor, 'cooperative_loan_disbursed',
    'cooperative_loan', p_loan_id,
    jsonb_build_object(
      'transaction_id', v_transaction_id,
      'amount', v_loan.principal_amount,
      'disbursed_on', current_date,
      'installment_count', v_loan.term_months
    )
  );

  return v_transaction_id;
end;
$$;

-- Legacy disbursed loans have no trustworthy disbursement date. Finance staff must
-- supply the actual date before a schedule can be created.
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

  select * into v_loan
  from public.cooperative_loans
  where id = p_loan_id
  for update;

  if not found or v_loan.status <> 'disbursed' then
    raise exception 'Only disbursed loans can be initialized';
  end if;

  if not exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = v_loan.organization_id
      and cm.user_id = v_actor
      and cm.is_active
      and cm.role in ('committee_admin','manager','treasurer','accountant')
  ) then
    raise exception 'Not authorized to initialize loan schedule';
  end if;

  if v_loan.disbursed_on is not null or exists (
    select 1 from public.cooperative_loan_installments where loan_id = p_loan_id
  ) then
    raise exception 'Loan schedule is already initialized';
  end if;

  update public.cooperative_loans
  set disbursed_on = p_disbursement_date, updated_at = now()
  where id = p_loan_id;

  perform public.create_cooperative_loan_installment_schedule(p_loan_id);

  insert into public.audit_log(
    organization_id, actor_id, action, entity_type, entity_id, after_data
  )
  values (
    v_loan.organization_id, v_actor, 'cooperative_loan_schedule_initialized',
    'cooperative_loan', p_loan_id,
    jsonb_build_object(
      'disbursed_on', p_disbursement_date,
      'installment_count', v_loan.term_months
    )
  );

  return v_loan.term_months;
end;
$$;

create or replace function public.record_cooperative_loan_repayment(
  p_loan_id uuid,
  p_amount numeric,
  p_payment_date date,
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
  v_paid numeric(14,2);
  v_total_due numeric(14,2);
  v_id uuid;
  v_transaction_id uuid;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Repayment amount must be positive'; end if;

  select * into v_loan
  from public.cooperative_loans
  where id = p_loan_id
  for update;

  if not found or v_loan.status <> 'disbursed' then
    raise exception 'Loan must be disbursed before repayment';
  end if;

  if not exists (
    select 1 from public.committee_memberships cm
    where cm.organization_id = v_loan.organization_id
      and cm.user_id = v_actor
      and cm.is_active
      and cm.role in ('committee_admin','manager','treasurer','accountant')
  ) then
    raise exception 'Not authorized to record repayment';
  end if;

  v_total_due := round(v_loan.principal_amount * (1 + v_loan.interest_rate / 100), 2);

  select coalesce(sum(amount), 0) into v_paid
  from public.cooperative_loan_repayments
  where organization_id = v_loan.organization_id
    and loan_id = p_loan_id;

  if round(v_paid + p_amount, 2) > v_total_due then
    raise exception 'Repayment exceeds outstanding loan amount';
  end if;

  insert into public.cooperative_loan_repayments(
    organization_id, loan_id, amount, payment_date, reference_number, received_by
  )
  values (
    v_loan.organization_id, p_loan_id, round(p_amount, 2),
    coalesce(p_payment_date, current_date), p_reference_number, v_actor
  )
  returning id into v_id;

  if exists (
    select 1 from public.cooperative_loan_installments where loan_id = p_loan_id
  ) then
    perform public.allocate_cooperative_loan_installment_payment(p_loan_id, round(p_amount, 2));
  end if;

  insert into public.financial_transactions(
    organization_id, membership_id, branch_id, transaction_type, amount,
    description, reference_number, status, created_by, approved_by, approved_at
  )
  values (
    v_loan.organization_id, v_loan.membership_id, v_loan.branch_id,
    'loan_repayment', round(p_amount, 2), 'Cooperative loan repayment',
    p_reference_number, 'approved', v_actor, v_actor, now()
  )
  returning id into v_transaction_id;

  if round(v_paid + p_amount, 2) >= v_total_due then
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
      'amount', round(p_amount, 2),
      'total_paid', round(v_paid + p_amount, 2)
    )
  );

  return v_id;
end;
$$;

revoke all on function public.disburse_cooperative_loan(uuid,text) from public, anon;
grant execute on function public.disburse_cooperative_loan(uuid,text) to authenticated;
revoke all on function public.initialize_cooperative_loan_installment_schedule(uuid,date) from public, anon;
grant execute on function public.initialize_cooperative_loan_installment_schedule(uuid,date) to authenticated;
revoke all on function public.record_cooperative_loan_repayment(uuid,numeric,date,text) from public, anon;
grant execute on function public.record_cooperative_loan_repayment(uuid,numeric,date,text) to authenticated;

-- The obsolete one-argument disbursement RPC must not bypass schedule creation or ledger posting.
revoke all on function public.disburse_cooperative_loan(uuid) from public, anon, authenticated;

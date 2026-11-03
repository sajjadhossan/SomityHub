-- Cover the composite loan foreign key and the common loan_id schedule lookup.
create index if not exists cooperative_loan_installments_loan_fk_idx
  on public.cooperative_loan_installments(organization_id, loan_id);

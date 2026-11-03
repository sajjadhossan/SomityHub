-- Installment rows are read-only through the client API; all writes go through audited RPCs.
revoke all on table public.cooperative_loan_installments from public, anon, authenticated;
grant select on table public.cooperative_loan_installments to authenticated;

-- Restrict installment table access to authenticated clients; RLS scopes visible rows.
revoke all on table public.cooperative_loan_installments from public, anon;
grant select on table public.cooperative_loan_installments to authenticated;

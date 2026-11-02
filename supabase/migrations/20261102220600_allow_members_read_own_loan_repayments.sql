drop policy if exists cooperative_loan_repayments_member_read on public.cooperative_loan_repayments;
create policy cooperative_loan_repayments_member_read
on public.cooperative_loan_repayments for select to authenticated
using (
  exists (
    select 1 from public.cooperative_loans l
    join public.committee_memberships cm
      on cm.organization_id=l.organization_id and cm.id=l.membership_id
    where l.organization_id=cooperative_loan_repayments.organization_id
      and l.id=cooperative_loan_repayments.loan_id
      and cm.user_id=(select auth.uid()) and cm.is_active
  )
);
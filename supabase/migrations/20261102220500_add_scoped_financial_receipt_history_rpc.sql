create or replace function public.get_financial_receipts(
  p_org_id uuid,
  p_membership_id uuid default null,
  p_limit integer default 100
) returns table(
  receipt_id uuid,
  transaction_id uuid,
  membership_id uuid,
  receipt_number text,
  verification_token uuid,
  issued_at timestamptz,
  transaction_type text,
  amount numeric,
  description text,
  transaction_status text
)
language plpgsql stable security definer set search_path = '' as $$
declare v_actor uuid := (select auth.uid()); v_limit integer;
begin
  if v_actor is null then raise exception 'Authentication required'; end if;
  v_limit := least(greatest(coalesce(p_limit,100),1),200);
  if p_membership_id is null then
    if not public.can_view_committee_finances(p_org_id) then
      raise exception 'Finance permission required to view all receipts';
    end if;
  elsif not exists(
    select 1 from public.committee_memberships cm
    where cm.organization_id=p_org_id and cm.id=p_membership_id and cm.is_active
      and (cm.user_id=v_actor or public.can_view_committee_finances(p_org_id))
  ) then
    raise exception 'You are not allowed to view these receipts';
  end if;
  return query
  select r.id,ft.id,ft.membership_id,r.receipt_number,r.verification_token,r.issued_at,
         ft.transaction_type,ft.amount,ft.description,ft.status
  from public.financial_receipts r
  join public.financial_transactions ft
    on ft.id=r.transaction_id and ft.organization_id=r.organization_id
  where r.organization_id=p_org_id
    and (p_membership_id is null or ft.membership_id=p_membership_id)
  order by r.issued_at desc
  limit v_limit;
end $$;
revoke all on function public.get_financial_receipts(uuid,uuid,integer) from public,anon;
grant execute on function public.get_financial_receipts(uuid,uuid,integer) to authenticated;
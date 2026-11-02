create or replace function public.record_approved_member_transaction()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status = 'approved'
     and old.status is distinct from 'approved' then
    -- Only member deposits and withdrawals affect member balances.
    -- Organization-level income/expense and loan cash movements stay in the cash ledger.
    if new.transaction_type not in ('deposit', 'withdrawal') then
      return new;
    end if;
    if new.membership_id is null then
      raise exception 'Member membership is required for balance ledger entry';
    end if;
    insert into public.member_balance_ledger (
      organization_id,membership_id,transaction_id,transaction_type,amount,signed_amount
    ) values (
      new.organization_id,new.membership_id,new.id,new.transaction_type,new.amount,
      case when new.transaction_type='deposit' then new.amount else -new.amount end
    );
    insert into public.transaction_events (
      organization_id,transaction_id,actor_id,event_type,event_data
    ) values (
      new.organization_id,new.id,new.approved_by,'member_balance_ledger_created',
      jsonb_build_object(
        'transaction_type',new.transaction_type,
        'amount',new.amount,
        'signed_amount',case when new.transaction_type='deposit' then new.amount else -new.amount end
      )
    );
  end if;
  return new;
end;
$$;
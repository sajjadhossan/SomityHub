-- Trigger-only helper: callers must not invoke this SECURITY DEFINER function via RPC.
revoke all on function public.assign_default_financial_branch() from public;
revoke all on function public.assign_default_financial_branch() from anon;
revoke all on function public.assign_default_financial_branch() from authenticated;

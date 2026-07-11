-- Switch customer order access from phone OTP to email OTP.
-- New orders must include an email; guest orders are linked once that email verifies.
alter table public.orders add constraint orders_email_required check (email is not null and btrim(email) <> '') not valid;

create or replace function public.claim_customer_orders() returns integer
language plpgsql security definer set search_path=public as $$
declare claimed integer;
begin
 if auth.uid() is null then raise exception 'Sign in before claiming orders'; end if;
 update public.orders set customer_id=auth.uid()
 where customer_id is null
   and lower(email)=lower(coalesce(auth.jwt()->>'email',''));
 get diagnostics claimed=row_count;
 return claimed;
end $$;
revoke all on function public.claim_customer_orders() from public;
grant execute on function public.claim_customer_orders() to authenticated;

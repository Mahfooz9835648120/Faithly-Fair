-- Customer order history: run this after the original Faithly Fair migration on an existing project.
alter table public.orders add column if not exists customer_id uuid references auth.users(id) on delete set null;
create index if not exists orders_customer_idx on public.orders(customer_id,created_at desc);

create or replace function public.claim_customer_orders() returns integer
language plpgsql security definer set search_path=public as $$
declare claimed integer;
begin
 if auth.uid() is null then raise exception 'Sign in before claiming orders'; end if;
 update public.orders
 set customer_id=auth.uid()
 where customer_id is null
   and right(regexp_replace(mobile,'[^0-9]','','g'),10)=right(regexp_replace(coalesce(auth.jwt()->>'phone',''),'[^0-9]','','g'),10);
 get diagnostics claimed=row_count;
 return claimed;
end $$;
revoke all on function public.claim_customer_orders() from public;
grant execute on function public.claim_customer_orders() to authenticated;

drop policy if exists "customer read own orders" on public.orders;
create policy "customer read own orders" on public.orders for select to authenticated using(customer_id=auth.uid());
drop policy if exists "customer read own order items" on public.order_items;
create policy "customer read own order items" on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()));

-- Faithly Fair initial schema. Run in a new Supabase project's SQL editor.
create extension if not exists pgcrypto;

create type public.order_state as enum ('new','confirmed','processing','shipped','delivered','cancelled');
create type public.payment_method as enum ('cod','upi');
create type public.payment_state as enum ('cod_due','awaiting_proof','proof_submitted','verified','rejected','paid');

create table public.admin_users (
 user_id uuid primary key references auth.users(id) on delete cascade,
 email text not null unique,
 created_at timestamptz not null default now()
);
create table public.products (
 id uuid primary key default gen_random_uuid(), name text not null, slug text not null unique,
 description text not null default '', price numeric(12,2) not null check(price>0),
 stock_quantity integer not null default 0 check(stock_quantity>=0), category text not null default 'bouquet' check(category in ('bouquet','hamper')), featured boolean not null default false,
 active boolean not null default true, display_order integer not null default 0,
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.product_images (
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade,
 url text not null, storage_path text, alt_text text, display_order integer not null default 0, created_at timestamptz not null default now()
);
create table public.hero_banners (
 id uuid primary key default gen_random_uuid(), eyebrow text not null default '', title text not null,
 description text not null default '', cta_label text not null default 'Shop gifts', cta_link text not null default '#shop',
 image_url text, active boolean not null default true, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.site_settings (
 key text primary key, value text not null, is_public boolean not null default false, updated_at timestamptz not null default now()
);
create table public.orders (
 id uuid primary key default gen_random_uuid(), customer_id uuid references auth.users(id) on delete set null, order_number text not null unique,
 customer_name text not null, mobile text not null, alternate_mobile text, email text not null,
 address_line1 text not null, address_line2 text, landmark text, city text not null, state text not null,
 pincode text not null check(pincode ~ '^[1-9][0-9]{5}$'), payment_method public.payment_method not null,
 payment_status public.payment_state not null, order_status public.order_state not null default 'new',
 subtotal numeric(12,2) not null check(subtotal>=0), total numeric(12,2) not null check(total>=0),
 upload_token uuid not null default gen_random_uuid(), proof_upload_expires_at timestamptz not null default (now()+interval '7 days'),
 notes text, created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create table public.order_items (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete restrict,
 product_id uuid references public.products(id) on delete set null, product_name text not null,
 unit_price numeric(12,2) not null check(unit_price>=0), quantity integer not null check(quantity>0),
 line_total numeric(12,2) not null check(line_total>=0), created_at timestamptz not null default now()
);
create table public.payment_proofs (
 id uuid primary key default gen_random_uuid(), order_id uuid not null references public.orders(id) on delete restrict,
 storage_path text not null unique, file_type text not null check(file_type in ('image/jpeg','image/png','image/webp')),
 file_size integer not null check(file_size>0 and file_size<=5242880), status text not null default 'submitted' check(status in ('submitted','verified','rejected')),
 submitted_at timestamptz not null default now(), reviewed_at timestamptz, reviewed_by uuid references auth.users(id), review_note text
);

create index products_active_order_idx on public.products(active,display_order);
create index orders_created_idx on public.orders(created_at desc);
create index orders_customer_idx on public.orders(customer_id,created_at desc);
create index orders_status_idx on public.orders(order_status,payment_status);
create index order_items_order_idx on public.order_items(order_id);
create index payment_proofs_order_idx on public.payment_proofs(order_id);

create or replace function public.is_admin() returns boolean language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.admin_users where user_id=auth.uid())
$$;
revoke all on function public.is_admin() from public; grant execute on function public.is_admin() to anon,authenticated;

create or replace function public.touch_updated_at() returns trigger language plpgsql as $$ begin new.updated_at=now(); return new; end $$;
create trigger products_touch before update on public.products for each row execute function public.touch_updated_at();
create trigger heroes_touch before update on public.hero_banners for each row execute function public.touch_updated_at();
create trigger orders_touch before update on public.orders for each row execute function public.touch_updated_at();

create sequence public.order_number_seq start 1001;
create or replace function public.create_guest_order(order_payload jsonb) returns jsonb
language plpgsql security definer set search_path=public as $$
declare c jsonb:=order_payload->'customer'; item jsonb; p public.products%rowtype; oid uuid; ono text; token uuid:=gen_random_uuid(); sum_total numeric:=0; method public.payment_method;
begin
 if jsonb_typeof(order_payload->'items')<>'array' or jsonb_array_length(order_payload->'items')=0 then raise exception 'Your gift bag is empty'; end if;
 if coalesce(c->>'name','')='' or (c->>'mobile') !~ '^[6-9][0-9]{9}$' or coalesce(c->>'email','')='' or position('@' in c->>'email')=0 or coalesce(c->>'address_line1','')='' or coalesce(c->>'city','')='' or coalesce(c->>'state','')='' or (c->>'pincode') !~ '^[1-9][0-9]{5}$' then raise exception 'Please check the required delivery details, including email'; end if;
 method:=(order_payload->>'payment_method')::public.payment_method;
 for item in select * from jsonb_array_elements(order_payload->'items') loop
  select * into p from public.products where id=(item->>'product_id')::uuid and active for update;
  if not found then raise exception 'A product is no longer available'; end if;
  if (item->>'quantity')::int<1 or p.stock_quantity<(item->>'quantity')::int then raise exception 'Not enough stock for %',p.name; end if;
  sum_total:=sum_total+p.price*(item->>'quantity')::int;
 end loop;
 ono:='FF-'||to_char(current_date,'YYMMDD')||'-'||lpad(nextval('public.order_number_seq')::text,5,'0');
 insert into public.orders(customer_id,order_number,customer_name,mobile,alternate_mobile,email,address_line1,address_line2,landmark,city,state,pincode,payment_method,payment_status,subtotal,total,upload_token)
 values(auth.uid(),ono,trim(c->>'name'),c->>'mobile',nullif(c->>'alternate_mobile',''),nullif(c->>'email',''),c->>'address_line1',nullif(c->>'address_line2',''),nullif(c->>'landmark',''),c->>'city',c->>'state',c->>'pincode',method,case when method='cod' then 'cod_due'::public.payment_state else 'awaiting_proof'::public.payment_state end,sum_total,sum_total,token) returning id into oid;
 for item in select * from jsonb_array_elements(order_payload->'items') loop
  select * into p from public.products where id=(item->>'product_id')::uuid for update;
  insert into public.order_items(order_id,product_id,product_name,unit_price,quantity,line_total) values(oid,p.id,p.name,p.price,(item->>'quantity')::int,p.price*(item->>'quantity')::int);
  update public.products set stock_quantity=stock_quantity-(item->>'quantity')::int where id=p.id;
 end loop;
 return jsonb_build_object('id',oid,'order_number',ono,'total',sum_total,'payment_method',method,'payment_status',case when method='cod' then 'cod_due' else 'awaiting_proof' end,'upload_token',token);
end $$;
revoke all on function public.create_guest_order(jsonb) from public; grant execute on function public.create_guest_order(jsonb) to anon,authenticated;

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
revoke all on function public.claim_customer_orders() from public; grant execute on function public.claim_customer_orders() to authenticated;

create or replace function public.submit_payment_proof(proof_token uuid,storage_path text,file_type text,file_size integer) returns void
language plpgsql security definer set search_path=public as $$
declare oid uuid;
begin
 select id into oid from public.orders where upload_token=proof_token and payment_method='upi' and payment_status in ('awaiting_proof','rejected') and proof_upload_expires_at>now() for update;
 if not found then raise exception 'This secure upload link is invalid or expired'; end if;
 if storage_path not like proof_token::text||'/%' then raise exception 'Invalid storage path'; end if;
 insert into public.payment_proofs(order_id,storage_path,file_type,file_size) values(oid,storage_path,file_type,file_size);
 update public.orders set payment_status='proof_submitted' where id=oid;
end $$;
revoke all on function public.submit_payment_proof(uuid,text,text,integer) from public; grant execute on function public.submit_payment_proof(uuid,text,text,integer) to anon,authenticated;

create or replace function public.can_upload_proof_path(object_name text) returns boolean
language sql stable security definer set search_path=public as $$
 select exists(select 1 from public.orders o where o.upload_token::text=(storage.foldername(object_name))[1] and o.payment_method='upi' and o.payment_status in ('awaiting_proof','rejected') and o.proof_upload_expires_at>now())
$$;
revoke all on function public.can_upload_proof_path(text) from public; grant execute on function public.can_upload_proof_path(text) to anon,authenticated;

alter table public.admin_users enable row level security; alter table public.products enable row level security;
alter table public.product_images enable row level security; alter table public.hero_banners enable row level security;
alter table public.site_settings enable row level security; alter table public.orders enable row level security;
alter table public.order_items enable row level security; alter table public.payment_proofs enable row level security;
create policy "admin manage admin list" on public.admin_users for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read active products" on public.products for select using(active or public.is_admin());
create policy "admin manage products" on public.products for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read product images" on public.product_images for select using(exists(select 1 from public.products p where p.id=product_id and (p.active or public.is_admin())));
create policy "admin manage product images" on public.product_images for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read active hero" on public.hero_banners for select using(active or public.is_admin());
create policy "admin manage hero" on public.hero_banners for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "public read safe settings" on public.site_settings for select using(is_public or public.is_admin());
create policy "admin manage settings" on public.site_settings for all to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin read orders" on public.orders for select to authenticated using(public.is_admin());
create policy "customer read own orders" on public.orders for select to authenticated using(customer_id=auth.uid());
create policy "admin update orders" on public.orders for update to authenticated using(public.is_admin()) with check(public.is_admin());
create policy "admin read order items" on public.order_items for select to authenticated using(public.is_admin());
create policy "customer read own order items" on public.order_items for select to authenticated using(exists(select 1 from public.orders o where o.id=order_id and o.customer_id=auth.uid()));
create policy "admin manage proofs" on public.payment_proofs for all to authenticated using(public.is_admin()) with check(public.is_admin());

insert into storage.buckets(id,name,public,file_size_limit,allowed_mime_types) values
 ('product-images','product-images',true,5242880,array['image/jpeg','image/png','image/webp']),
 ('payment-proofs','payment-proofs',false,5242880,array['image/jpeg','image/png','image/webp']) on conflict(id) do update set public=excluded.public,file_size_limit=excluded.file_size_limit,allowed_mime_types=excluded.allowed_mime_types;
create policy "public view product files" on storage.objects for select using(bucket_id='product-images');
create policy "admin manage product files" on storage.objects for all to authenticated using(bucket_id='product-images' and public.is_admin()) with check(bucket_id='product-images' and public.is_admin());
create policy "guest upload proof with valid token" on storage.objects for insert to anon,authenticated with check(bucket_id='payment-proofs' and public.can_upload_proof_path(name));
create policy "admin read proof files" on storage.objects for select to authenticated using(bucket_id='payment-proofs' and public.is_admin());
create policy "admin delete proof files" on storage.objects for delete to authenticated using(bucket_id='payment-proofs' and public.is_admin());

insert into public.site_settings(key,value,is_public) values
 ('business_name','Faithly Fair',true),('email','Fairyfaithly@gmail.com',true),('whatsapp','918920925880',true),('upi_id','8920925990@fam',true),('upi_payee_name','Faithly Fair',true)
on conflict(key) do update set value=excluded.value,is_public=excluded.is_public;
insert into public.hero_banners(eyebrow,title,description,cta_label,cta_link) values('Flowers that speak from the heart','Bouquets made for unforgettable moments.','Fresh, expressive arrangements designed to turn every feeling into something beautiful.','Explore bouquets','/shop');
insert into public.products(name,slug,description,price,stock_quantity,category,featured,display_order) values
 ('Blushing Rose Bouquet','blushing-rose-bouquet','Soft pink roses, seasonal greens and a flowing satin wrap.',899,12,'bouquet',true,1),
 ('Ivory Garden Bouquet','ivory-garden-bouquet','An elegant hand-tied mix in cream, blush and fresh green tones.',1299,8,'bouquet',true,2),
 ('Petite Love Bouquet','petite-love-bouquet','A charming compact bouquet for birthdays, thank-yous and just because.',649,15,'bouquet',true,3),
 ('Sweetheart Gift Hamper','sweetheart-gift-hamper','A secondary little luxury filled with treats and thoughtful keepsakes.',1499,7,'hamper',false,4);

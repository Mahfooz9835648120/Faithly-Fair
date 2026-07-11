-- Apply this migration only when upgrading an existing Faithly Fair project.
alter table public.products add column if not exists category text not null default 'bouquet';
alter table public.products drop constraint if exists products_category_check;
alter table public.products add constraint products_category_check check(category in ('bouquet','hamper'));
update public.products set category='hamper' where lower(name) like '%hamper%' or lower(slug) like '%hamper%';
update public.hero_banners set eyebrow='Flowers that speak from the heart',title='Bouquets made for unforgettable moments.',description='Fresh, expressive arrangements designed to turn every feeling into something beautiful.',cta_label='Explore bouquets',cta_link='/shop' where active=true;

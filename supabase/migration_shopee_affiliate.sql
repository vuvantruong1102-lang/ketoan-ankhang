-- =====================================================================
-- PANEL ĐỐI SOÁT SHOPEE AFFILIATE (độc lập, không đụng dữ liệu kế toán)
-- Chạy trong Supabase > SQL Editor. An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

-- 1. Hoa hồng affiliate nhập tay hàng ngày (bảng 1)
create table if not exists shopee_affiliate (
  id            bigint generated always as identity primary key,
  tx_date       date not null,
  amount        numeric(18,2) not null default 0 check (amount >= 0),
  payment_code  text,                         -- mã thanh toán Shopee (3-5 ngày chung 1 mã)
  note          text,
  created_at    timestamptz not null default now()
);
create index if not exists idx_shopee_aff_date on shopee_affiliate (tx_date);
create index if not exists idx_shopee_aff_code on shopee_affiliate (payment_code);

-- 2. Đối soát theo khoảng ngày (bảng 3)
create table if not exists shopee_reconcile (
  id             bigint generated always as identity primary key,
  reconcile_date date not null,               -- ngày đối soát
  period_from    date not null,               -- khoảng đối soát: từ ngày
  period_to      date not null,               -- đến ngày
  shopee_amount  numeric(18,2) not null default 0,  -- số tiền Shopee đối soát
  note           text,
  created_at     timestamptz not null default now(),
  check (period_to >= period_from)
);
create index if not exists idx_shopee_rec_period on shopee_reconcile (period_from, period_to);

-- 3. Cấp quyền + RLS (một người dùng, giống các bảng khác)
grant all on shopee_affiliate, shopee_reconcile to anon, authenticated, service_role;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='ketoan' and tablename='shopee_affiliate') then
    alter table ketoan.shopee_affiliate enable row level security;
    create policy shopee_affiliate_auth on ketoan.shopee_affiliate
      for all to authenticated using (true) with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname='ketoan' and tablename='shopee_reconcile') then
    alter table ketoan.shopee_reconcile enable row level security;
    create policy shopee_reconcile_auth on ketoan.shopee_reconcile
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- =====================================================================
-- Xong. Hai bảng này độc lập, không liên quan báo cáo doanh thu/thuế.
-- =====================================================================

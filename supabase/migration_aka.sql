-- =====================================================================
-- ĐỐI SOÁT FACEBOOK AKA MEDIA
-- - Tiền nạp: tự lấy từ giao dịch CHI (direction='out') trong bank_tx
--   có counterparty chứa chuỗi lọc (mặc định 'AKA MEDIA').
-- - Tiền chi (nghiệm thu): nhập tay, lưu ở bảng aka_acceptance.
-- - Số dư đầu + bộ lọc tên: lưu ở bảng aka_settings (1 dòng duy nhất).
-- Panel độc lập, không đụng chi phí/lợi nhuận.
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

-- 1. Cấu hình (1 dòng): số dư đầu + chuỗi lọc tên đối ứng
create table if not exists aka_settings (
  id             int primary key default 1 check (id = 1),
  opening_balance numeric(18,2) not null default 0,
  name_filter    text not null default 'AKA MEDIA',
  updated_at     timestamptz not null default now()
);
insert into aka_settings (id) values (1) on conflict (id) do nothing;

-- 2. Nghiệm thu (tiền chi), nhập tay
create table if not exists aka_acceptance (
  id          bigint generated always as identity primary key,
  tx_date     date not null,
  amount      numeric(18,2) not null default 0 check (amount >= 0),
  description text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_aka_acc_date on aka_acceptance (tx_date);

-- 3. Loại trừ giao dịch ngân hàng nhận nhầm (chỉnh tay): lưu id bank_tx bị bỏ
create table if not exists aka_excluded (
  bank_tx_id  bigint primary key references ketoan.bank_tx(id) on delete cascade,
  created_at  timestamptz not null default now()
);

-- 3b. Giao dịch NẠP nhập tay (ngoài phần tự lấy từ ngân hàng)
create table if not exists aka_deposit (
  id          bigint generated always as identity primary key,
  tx_date     date not null,
  amount      numeric(18,2) not null default 0 check (amount >= 0),
  description text,
  created_at  timestamptz not null default now()
);
create index if not exists idx_aka_dep_date on aka_deposit (tx_date);

-- 4. Quyền + RLS
grant all on aka_settings, aka_acceptance, aka_excluded, aka_deposit to anon, authenticated, service_role;
grant all on all sequences in schema ketoan to anon, authenticated, service_role;

do $$
declare t text;
begin
  foreach t in array array['aka_settings','aka_acceptance','aka_excluded','aka_deposit'] loop
    if not exists (select 1 from pg_policies where schemaname='ketoan' and tablename=t) then
      execute format('alter table ketoan.%I enable row level security;', t);
      execute format($p$create policy %1$s_auth on ketoan.%1$I
        for all to authenticated using (true) with check (true);$p$, t);
    end if;
  end loop;
end $$;

-- =====================================================================
-- Xong.
-- =====================================================================

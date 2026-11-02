-- =====================================================================
-- BẢNG CHI PHÍ (nhập từng khoản): ngày, số tiền, loại, nội dung.
-- Loại: 'sale' (bán hàng), 'admin' (quản lý), hoặc loại tự nhập.
-- Tự tổng hợp sang Kết quả kinh doanh (cộng thêm vào chi phí hóa đơn).
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

create table if not exists expenses (
  id            bigint generated always as identity primary key,
  exp_date      date not null,
  amount        numeric(18,2) not null default 0 check (amount >= 0),
  -- loại chi phí: lưu nhãn tự do; mặc định gợi ý 'Bán hàng' / 'Quản lý'
  category      text not null default 'Quản lý',
  description   text,
  created_at    timestamptz not null default now()
);
comment on table expenses is 'Chi phí nhập tay: bán hàng, quản lý, hoặc loại khác.';
create index if not exists idx_expenses_date on expenses (exp_date);

grant all on expenses to anon, authenticated, service_role;
grant all on all sequences in schema ketoan to anon, authenticated, service_role;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='ketoan' and tablename='expenses') then
    alter table ketoan.expenses enable row level security;
    create policy expenses_auth on ketoan.expenses
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- =====================================================================
-- Xong. Bảng pl_adjustments (lương/chi phí khác cũ) vẫn giữ trong DB
-- nhưng không còn dùng ở giao diện — không xóa để an toàn.
-- =====================================================================

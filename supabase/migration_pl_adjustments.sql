-- =====================================================================
-- BẢNG: các khoản nhập tay theo quý cho Kết quả kinh doanh
-- (Lương, Chi phí khác) để tính Lợi nhuận chịu thuế.
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

create table if not exists pl_adjustments (
  id            bigint generated always as identity primary key,
  year          int  not null,
  quarter       int  not null check (quarter between 1 and 4),
  salary        numeric(18,2) not null default 0,   -- lương
  other_expense numeric(18,2) not null default 0,   -- chi phí khác
  note          text,
  created_at    timestamptz not null default now(),
  unique (year, quarter)
);
comment on table pl_adjustments is 'Lương + chi phí khác nhập tay theo quý (cho KQKD).';

grant all on pl_adjustments to anon, authenticated, service_role;
grant all on all sequences in schema ketoan to anon, authenticated, service_role;

do $$
begin
  if not exists (select 1 from pg_policies where schemaname='ketoan' and tablename='pl_adjustments') then
    alter table ketoan.pl_adjustments enable row level security;
    create policy pl_adjustments_auth on ketoan.pl_adjustments
      for all to authenticated using (true) with check (true);
  end if;
end $$;

-- =====================================================================
-- Xong.
-- =====================================================================

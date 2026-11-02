-- =====================================================================
-- SETUP.SQL — TẠO TOÀN BỘ DATABASE CHO APP KẾ TOÁN (chạy MỘT LẦN)
-- Dùng cho project Supabase MỚI. Chạy trong SQL Editor, rồi chạy schema_rls.sql.
-- An toàn chạy lại nhiều lần — KHÔNG xóa dữ liệu đã có.
-- Mọi bảng nằm trong schema "ketoan", tách biệt schema public.
-- =====================================================================



-- ========== schema.sql ==========

-- =====================================================================
-- PHẦN MỀM KẾ TOÁN NỘI BỘ YOKOOL — GIAI ĐOẠN 1
-- Chế độ: Thông tư 133/2016. Mô hình đơn giản hóa (không bút toán kép).
-- Nền tảng: Supabase (PostgreSQL)
-- Cách dùng: dán toàn bộ file này vào Supabase > SQL Editor > Run
-- Tiền tệ: VND. Nội bộ lưu numeric (giữ số lẻ cho giá vốn bình quân);
--          làm tròn về số nguyên đồng khi hiển thị ở tầng app.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 0. SCHEMA RIÊNG CHO APP KẾ TOÁN
--    App này dùng CHUNG project Supabase với nhiều app khác, nên TẤT CẢ
--    bảng nằm trong schema riêng "ketoan" — KHÔNG đụng schema public của
--    các app kia. Muốn gỡ sạch app kế toán sau này chỉ cần:
--        drop schema ketoan cascade;
--    (chỉ xóa đúng app kế toán, không ảnh hưởng app khác).
-- ---------------------------------------------------------------------
-- CẢNH BÁO: dòng dưới xóa và tạo lại schema ketoan (chỉ app kế toán).
-- An toàn với app khác. Khi đã có dữ liệu thật, BỎ dòng drop đi.
create schema if not exists ketoan;

-- Mọi lệnh bên dưới chạy trong schema ketoan nhờ search_path này.
set search_path = ketoan, public;

-- ---------------------------------------------------------------------
-- 1. KỲ KẾ TOÁN (theo quý)
-- ---------------------------------------------------------------------
create table periods (
  id          bigint generated always as identity primary key,
  year        int  not null,
  quarter     int  not null check (quarter between 1 and 4),
  status      text not null default 'open' check (status in ('open','closed')),
  closed_at   timestamptz,
  created_at  timestamptz not null default now(),
  unique (year, quarter)
);
comment on table periods is 'Các quý kế toán. status=closed sau khi bấm "Chốt kỳ".';

-- Hàm tiện ích: từ một ngày suy ra (year, quarter)
create or replace function period_of(d date)
returns table(year int, quarter int)
language sql immutable
set search_path = ketoan, public as $$
  select extract(year from d)::int,
         ((extract(month from d)::int - 1) / 3 + 1)::int;
$$;

-- ---------------------------------------------------------------------
-- 2. DANH MỤC ĐỐI TÁC (nhà cung cấp + khách hàng, dùng chung)
-- ---------------------------------------------------------------------
create table partners (
  id          bigint generated always as identity primary key,
  code        text unique,                       -- mã nội bộ, tùy chọn
  name        text not null,
  tax_code    text,                              -- MST
  address     text,
  phone       text,
  -- một đối tác có thể vừa là NCC vừa là khách; đánh dấu để lọc nhanh
  is_supplier boolean not null default false,
  is_customer boolean not null default false,
  note        text,
  created_at  timestamptz not null default now()
);
comment on table partners is 'Nhà cung cấp và khách hàng. Dùng chung một bảng.';
create index idx_partners_name on partners (name);
create index idx_partners_tax  on partners (tax_code);

-- ---------------------------------------------------------------------
-- 3. DANH MỤC SẢN PHẨM (theo SKU)
-- ---------------------------------------------------------------------
create table products (
  id          bigint generated always as identity primary key,
  sku         text not null unique,              -- mã SKU
  name        text not null,
  unit        text,                              -- đơn vị tính (cái, hộp...)
  -- hàng hóa: có tồn kho + giá vốn; dịch vụ: chỉ chi phí/doanh thu, không tồn
  kind        text not null default 'goods' check (kind in ('goods','service')),
  note        text,
  is_active   boolean not null default true,
  created_at  timestamptz not null default now()
);
comment on table products is 'Sản phẩm theo SKU. kind=goods có tồn kho, service thì không.';
create index idx_products_name on products (name);

-- ---------------------------------------------------------------------
-- 4. HÓA ĐƠN (đầu vào / đầu ra)
-- ---------------------------------------------------------------------
create table invoices (
  id            bigint generated always as identity primary key,
  -- 'in' = hóa đơn mua vào; 'out' = hóa đơn bán ra
  direction     text not null check (direction in ('in','out')),
  invoice_no    text,                            -- số hóa đơn
  symbol        text,                            -- ký hiệu hóa đơn (vd 1C26MYY)
  invoice_date  date not null,
  partner_id    bigint references partners(id),
  -- phân loại nội dung chính của hóa đơn
  category      text not null default 'goods' check (category in ('goods','service')),
  -- CHỈ áp dụng cho hóa đơn mua (direction='in'):
  -- true  = đủ điều kiện khấu trừ -> thuế vào "thuế đầu vào được khấu trừ"
  -- false = không đủ điều kiện    -> thuế gộp vào chi phí/giá trị hàng
  vat_deductible boolean not null default true,
  description   text,
  -- tổng tiền được tính lại từ invoice_items bằng trigger (không nhập tay)
  amount_before_tax numeric(18,2) not null default 0,  -- tổng tiền chưa thuế
  tax_amount        numeric(18,2) not null default 0,  -- tổng tiền thuế
  amount_total      numeric(18,2) not null default 0,  -- tổng thanh toán
  created_at    timestamptz not null default now()
);
comment on table invoices is 'Đầu hóa đơn. Tổng tiền tự tính từ invoice_items.';
comment on column invoices.vat_deductible is
  'Chỉ dùng cho hóa đơn mua. false=thuế không được khấu trừ, gộp vào chi phí.';
create index idx_invoices_date      on invoices (invoice_date);
create index idx_invoices_direction on invoices (direction);
create index idx_invoices_partner   on invoices (partner_id);

-- ---------------------------------------------------------------------
-- 5. CHI TIẾT DÒNG HÓA ĐƠN
-- ---------------------------------------------------------------------
create table invoice_items (
  id            bigint generated always as identity primary key,
  invoice_id    bigint not null references invoices(id) on delete cascade,
  product_id    bigint references products(id),
  description   text,                            -- diễn giải (dịch vụ có thể không có SKU)
  -- Cho phép SỐ ÂM để phục vụ hóa đơn điều chỉnh giảm (SL/tiền/thuế âm).
  quantity      numeric(18,4) not null default 1,
  unit_price    numeric(18,4) not null default 0,  -- đơn giá chưa thuế
  vat_rate      numeric(5,2)  not null default 8 check (vat_rate in (0,5,8,10)),
  -- GHI ĐÈ THỦ CÔNG (tùy chọn): để NULL = tự tính; điền số = dùng đúng số này.
  -- Dùng khi số trên hóa đơn NCC lệch do làm tròn, hoặc hóa đơn điều chỉnh (âm).
  amount_override numeric(18,2),
  tax_override    numeric(18,2),
  -- các cột dưới tự tính bằng trigger (ưu tiên số ghi đè nếu có)
  line_before_tax numeric(18,2) not null default 0,  -- quantity * unit_price (hoặc amount_override)
  line_tax        numeric(18,2) not null default 0,  -- line_before_tax * vat_rate/100 (hoặc tax_override)
  line_total      numeric(18,2) not null default 0,  -- before + tax
  created_at    timestamptz not null default now()
);
comment on table invoice_items is 'Dòng chi tiết hóa đơn. Thành tiền + thuế tự tính, có thể ghi đè tay.';
create index idx_items_invoice on invoice_items (invoice_id);
create index idx_items_product on invoice_items (product_id);

-- ---------------------------------------------------------------------
-- 6. TỒN KHO ĐẦU KỲ (import Excel). Mỗi SKU 1 dòng cho 1 quý mốc.
-- ---------------------------------------------------------------------
create table inventory_opening (
  id          bigint generated always as identity primary key,
  product_id  bigint not null references products(id),
  year        int  not null,
  quarter     int  not null check (quarter between 1 and 4),
  quantity    numeric(18,4) not null default 0,  -- số lượng tồn đầu
  unit_cost   numeric(18,4) not null default 0,  -- đơn giá vốn tồn đầu
  created_at  timestamptz not null default now(),
  unique (product_id, year, quarter)
);
comment on table inventory_opening is 'Tồn kho đầu kỳ theo SKU + quý. Nhập tay hoặc import Excel.';

-- ---------------------------------------------------------------------
-- 7. GIÁ VỐN CHỐT THEO KỲ (sinh ra khi bấm "Chốt kỳ")
--    Lưu đơn giá bình quân gia quyền cuối kỳ + giá vốn đã xuất trong kỳ.
-- ---------------------------------------------------------------------
create table cogs_period (
  id             bigint generated always as identity primary key,
  product_id     bigint not null references products(id),
  year           int not null,
  quarter        int not null check (quarter between 1 and 4),
  opening_qty    numeric(18,4) not null default 0,
  opening_value  numeric(18,2) not null default 0,
  purchase_qty   numeric(18,4) not null default 0,
  purchase_value numeric(18,2) not null default 0,
  avg_unit_cost  numeric(18,4) not null default 0,  -- (opening_value+purchase_value)/(opening_qty+purchase_qty)
  sold_qty       numeric(18,4) not null default 0,
  cogs_value     numeric(18,2) not null default 0,  -- sold_qty * avg_unit_cost
  closing_qty    numeric(18,4) not null default 0,
  closing_value  numeric(18,2) not null default 0,
  created_at     timestamptz not null default now(),
  unique (product_id, year, quarter)
);
comment on table cogs_period is 'Kết quả tính giá vốn BQGQ cuối kỳ. Sinh khi chốt kỳ.';

-- ---------------------------------------------------------------------
-- 8. SỔ TIỀN MẶT (nhập tay, theo dõi số dư)
-- ---------------------------------------------------------------------
create table cash_book (
  id          bigint generated always as identity primary key,
  tx_date     date not null,
  direction   text not null check (direction in ('in','out')),  -- thu / chi
  amount      numeric(18,2) not null check (amount >= 0),
  description text,
  partner_id  bigint references partners(id),  -- nhãn đối tác (tùy chọn), để tự đối chiếu
  created_at  timestamptz not null default now()
);
comment on table cash_book is 'Sổ quỹ tiền mặt. Độc lập, chỉ theo dõi dòng tiền + số dư.';
create index idx_cash_date on cash_book (tx_date);

-- ---------------------------------------------------------------------
-- 9. SỔ NGÂN HÀNG (nhập tay, theo dõi số dư)
-- ---------------------------------------------------------------------
create table bank_book (
  id           bigint generated always as identity primary key,
  tx_date      date not null,
  direction    text not null check (direction in ('in','out')),
  amount       numeric(18,2) not null check (amount >= 0),
  description  text,
  bank_account text,                             -- tên/số TK ngân hàng
  partner_id   bigint references partners(id),   -- nhãn đối tác (tùy chọn)
  created_at   timestamptz not null default now()
);
comment on table bank_book is 'Sổ ngân hàng. Độc lập, chỉ theo dõi dòng tiền + số dư.';
create index idx_bank_date on bank_book (tx_date);

-- =====================================================================
-- 10. TRIGGER: tự tính thành tiền trên từng dòng hóa đơn,
--     và cập nhật tổng tiền trên đầu hóa đơn.
-- =====================================================================

-- 10a. tính line_before_tax / line_tax / line_total cho 1 dòng
create or replace function fn_item_compute()
returns trigger language plpgsql as $$
begin
  -- Thành tiền chưa thuế: dùng số ghi đè nếu có, không thì SL × đơn giá.
  new.line_before_tax := coalesce(new.amount_override,
                                  round(new.quantity * new.unit_price, 2));
  -- Tiền thuế: dùng số ghi đè nếu có (để khớp đúng hóa đơn NCC), không thì tự tính.
  new.line_tax        := coalesce(new.tax_override,
                                  round(new.line_before_tax * new.vat_rate / 100.0, 2));
  new.line_total      := new.line_before_tax + new.line_tax;
  return new;
end $$;

create trigger trg_item_compute
  before insert or update on invoice_items
  for each row execute function fn_item_compute();

-- 10b. cộng lại tổng của đầu hóa đơn mỗi khi dòng thay đổi
create or replace function fn_invoice_rollup()
returns trigger language plpgsql as $$
declare
  v_invoice bigint := coalesce(new.invoice_id, old.invoice_id);
begin
  update invoices i set
    amount_before_tax = coalesce(s.b,0),
    tax_amount        = coalesce(s.t,0),
    amount_total      = coalesce(s.b,0) + coalesce(s.t,0)
  from (
    select sum(line_before_tax) b, sum(line_tax) t
    from invoice_items where invoice_id = v_invoice
  ) s
  where i.id = v_invoice;
  return null;
end $$;

create trigger trg_invoice_rollup
  after insert or update or delete on invoice_items
  for each row execute function fn_invoice_rollup();

-- =====================================================================
-- 11. VIEW BÁO CÁO
-- =====================================================================

-- 11a. TỒN KHO HIỆN TẠI (số lượng) — suy từ hóa đơn + tồn đầu kỳ
--      Giá trị tồn chỉ chính xác sau khi chốt kỳ (cogs_period).
create view v_inventory_onhand as
with opening as (
  select product_id, sum(quantity) qty, sum(quantity*unit_cost) val
  from inventory_opening group by product_id
),
moves as (
  select ii.product_id,
         sum(case when inv.direction='in'  then ii.quantity else 0 end) in_qty,
         sum(case when inv.direction='out' then ii.quantity else 0 end) out_qty
  from invoice_items ii
  join invoices inv on inv.id = ii.invoice_id
  where ii.product_id is not null
  group by ii.product_id
)
select p.id as product_id, p.sku, p.name, p.unit,
       coalesce(o.qty,0)                                        as opening_qty,
       coalesce(m.in_qty,0)                                     as purchased_qty,
       coalesce(m.out_qty,0)                                    as sold_qty,
       coalesce(o.qty,0) + coalesce(m.in_qty,0) - coalesce(m.out_qty,0) as onhand_qty
from products p
left join opening o on o.product_id = p.id
left join moves   m on m.product_id = p.id
where p.kind = 'goods';
comment on view v_inventory_onhand is 'Tồn kho hiện tại theo số lượng (opening + mua - bán).';

-- 11b. VAT PHẢI NỘP THEO QUÝ
--      Thuế đầu ra (bán) - Thuế đầu vào được khấu trừ (mua & vat_deductible)
create view v_vat_by_quarter as
select
  extract(year from invoice_date)::int                       as year,
  ((extract(month from invoice_date)::int - 1)/3 + 1)::int   as quarter,
  sum(case when direction='out' then tax_amount else 0 end)  as output_vat,
  sum(case when direction='in' and vat_deductible
           then tax_amount else 0 end)                       as deductible_input_vat,
  sum(case when direction='out' then tax_amount else 0 end)
    - sum(case when direction='in' and vat_deductible
               then tax_amount else 0 end)                   as vat_payable
from invoices
group by 1,2
order by 1,2;
comment on view v_vat_by_quarter is
  'VAT phải nộp mỗi quý. Âm = còn được khấu trừ chuyển kỳ sau.';

-- 11c. KẾT QUẢ KINH DOANH THEO QUÝ (tạm tính)
--      Doanh thu = tổng chưa thuế hóa đơn bán.
--      Giá vốn   = lấy từ cogs_period (chỉ có sau khi chốt kỳ).
--      Chi phí   = tổng chưa thuế hóa đơn mua loại dịch vụ
--                  + phần thuế không khấu trừ của hóa đơn mua.
create view v_pl_by_quarter as
with rev as (  -- doanh thu thuần
  select extract(year from invoice_date)::int y,
         ((extract(month from invoice_date)::int-1)/3+1)::int q,
         sum(amount_before_tax) revenue
  from invoices where direction='out' group by 1,2
),
exp_service as (  -- chi phí từ hóa đơn mua dịch vụ
  select extract(year from invoice_date)::int y,
         ((extract(month from invoice_date)::int-1)/3+1)::int q,
         sum(amount_before_tax) expense
  from invoices where direction='in' and category='service' group by 1,2
),
exp_nondeduct as (  -- thuế không khấu trừ -> tính vào chi phí
  select extract(year from invoice_date)::int y,
         ((extract(month from invoice_date)::int-1)/3+1)::int q,
         sum(tax_amount) nd_tax
  from invoices where direction='in' and vat_deductible=false group by 1,2
),
cogs as (  -- giá vốn đã chốt
  select year y, quarter q, sum(cogs_value) cogs
  from cogs_period group by 1,2
)
select
  coalesce(r.y,s.y,n.y,c.y) as year,
  coalesce(r.q,s.q,n.q,c.q) as quarter,
  coalesce(r.revenue,0)                                   as revenue,
  coalesce(c.cogs,0)                                      as cogs,
  coalesce(s.expense,0) + coalesce(n.nd_tax,0)            as expenses,
  coalesce(r.revenue,0) - coalesce(c.cogs,0)
    - coalesce(s.expense,0) - coalesce(n.nd_tax,0)        as profit
from rev r
full join exp_service   s on s.y=r.y and s.q=r.q
full join exp_nondeduct n on n.y=coalesce(r.y,s.y) and n.q=coalesce(r.q,s.q)
full join cogs          c on c.y=coalesce(r.y,s.y,n.y) and c.q=coalesce(r.q,s.q,n.q)
order by 1,2;
comment on view v_pl_by_quarter is
  'KQKD theo quý. Giá vốn chỉ có sau khi chốt kỳ (nếu trống = chưa chốt).';

-- =====================================================================
-- 12. HÀM CHỐT KỲ: tính giá vốn BQGQ cuối kỳ cho một quý
--     Gọi: select close_period(2026, 1);
-- =====================================================================
create or replace function close_period(p_year int, p_quarter int)
returns void language plpgsql
set search_path = ketoan, public as $$
declare
  m_start date := make_date(p_year, (p_quarter-1)*3 + 1, 1);
  m_end   date := (make_date(p_year, (p_quarter-1)*3 + 1, 1) + interval '3 months')::date;
begin
  if exists (select 1 from periods
             where year=p_year and quarter=p_quarter and status='closed') then
    raise exception 'Kỳ %/Q% đã được chốt.', p_year, p_quarter;
  end if;
  delete from cogs_period where year=p_year and quarter=p_quarter;
  insert into cogs_period(
    product_id, year, quarter,
    opening_qty, opening_value, purchase_qty, purchase_value,
    avg_unit_cost, sold_qty, cogs_value, closing_qty, closing_value)
  select
    p.id, p_year, p_quarter,
    coalesce(o.qty,0), coalesce(o.val,0),
    coalesce(pu.qty,0), coalesce(pu.val,0),
    case when (coalesce(o.qty,0) + coalesce(pu.qty,0)) > 0
         then round((coalesce(o.val,0) + coalesce(pu.val,0))
                    / (coalesce(o.qty,0) + coalesce(pu.qty,0)), 4) else 0 end,
    coalesce(sa.qty,0),
    round(coalesce(sa.qty,0) * case when (coalesce(o.qty,0)+coalesce(pu.qty,0))>0
         then (coalesce(o.val,0)+coalesce(pu.val,0))
              /(coalesce(o.qty,0)+coalesce(pu.qty,0)) else 0 end, 2),
    (coalesce(o.qty,0) + coalesce(pu.qty,0) - coalesce(sa_all.qty,0)),
    round((coalesce(o.qty,0) + coalesce(pu.qty,0) - coalesce(sa_all.qty,0))
          * case when (coalesce(o.qty,0)+coalesce(pu.qty,0))>0
         then (coalesce(o.val,0)+coalesce(pu.val,0))
              /(coalesce(o.qty,0)+coalesce(pu.qty,0)) else 0 end, 2)
  from products p
  left join lateral (
    select sum(quantity) qty, sum(quantity*unit_cost) val
    from inventory_opening
    where product_id=p.id
      and (year < p_year or (year = p_year and quarter <= p_quarter))
  ) o on true
  left join lateral (
    select coalesce(sum(ii.quantity),0) qty,
           coalesce(sum(ii.line_before_tax),0) val
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='in' and i.invoice_date < m_end
  ) pu on true
  left join lateral (
    select coalesce(sum(ii.quantity),0) qty
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='out'
      and i.invoice_date >= m_start and i.invoice_date < m_end
  ) sa on true
  left join lateral (
    select coalesce(sum(ii.quantity),0) qty
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='out' and i.invoice_date < m_end
  ) sa_all on true
  where p.kind='goods';
  insert into periods(year, quarter, status, closed_at)
  values (p_year, p_quarter, 'closed', now())
  on conflict (year, quarter)
  do update set status='closed', closed_at=now();
end $$;

create or replace function reopen_period(p_year int, p_quarter int)
returns void language plpgsql
set search_path = ketoan, public as $$
begin
  delete from cogs_period where year=p_year and quarter=p_quarter;
  update periods set status='open', closed_at=null
    where year=p_year and quarter=p_quarter;
end $$;
comment on function close_period is
  'Chốt kỳ: giá vốn BQGQ lũy kế (gồm hàng mua quý trước), ghi vào cogs_period.';


-- ========== migration_v2.sql ==========

-- =====================================================================
-- MIGRATION V2: chống trùng hóa đơn, VAT khấu trừ kỳ trước, tài khoản ngân hàng
-- Chạy trong Supabase > SQL Editor. An toàn chạy nhiều lần.
-- Mọi thứ trong schema ketoan — không đụng app khác.
-- =====================================================================

set search_path = ketoan, public;

-- ---------------------------------------------------------------------
-- 1. CHẶN TRÙNG SỐ HÓA ĐƠN + CÙNG NHÀ CUNG CẤP
--    (chỉ áp dụng khi có cả số HĐ và NCC; bỏ qua dòng thiếu một trong hai)
-- ---------------------------------------------------------------------
create unique index if not exists uq_invoice_no_partner
  on ketoan.invoices (direction, partner_id, invoice_no)
  where invoice_no is not null and partner_id is not null;

-- ---------------------------------------------------------------------
-- 2. THUẾ GTGT ĐƯỢC KHẤU TRỪ KỲ TRƯỚC CHUYỂN SANG (theo quý)
-- ---------------------------------------------------------------------
create table if not exists vat_carryover (
  id          bigint generated always as identity primary key,
  year        int  not null,
  quarter     int  not null check (quarter between 1 and 4),
  amount      numeric(18,2) not null default 0,  -- số thuế còn được khấu trừ kỳ trước
  note        text,
  created_at  timestamptz not null default now(),
  unique (year, quarter)
);
comment on table vat_carryover is 'Thuế GTGT còn được khấu trừ chuyển sang từ kỳ trước (nhập tay theo quý).';

-- ---------------------------------------------------------------------
-- 3. TÀI KHOẢN NGÂN HÀNG + GIAO DỊCH
-- ---------------------------------------------------------------------
create table if not exists bank_accounts (
  id            bigint generated always as identity primary key,
  name          text not null,                  -- tên gợi nhớ: "VCB chính", "ACB"...
  bank          text,                           -- tên ngân hàng
  account_no    text,                           -- số tài khoản
  opening_balance numeric(18,2) not null default 0,  -- số dư đầu kỳ
  is_active     boolean not null default true,
  note          text,
  created_at    timestamptz not null default now()
);
comment on table bank_accounts is 'Danh mục tài khoản ngân hàng của công ty.';

create table if not exists bank_tx (
  id           bigint generated always as identity primary key,
  account_id   bigint not null references ketoan.bank_accounts(id) on delete cascade,
  tx_date      date not null,
  direction    text not null check (direction in ('in','out')),  -- thu / chi
  amount       numeric(18,2) not null check (amount >= 0),
  description  text,
  counterparty text,                            -- tên TK đối ứng (Remitter's account name)
  created_at   timestamptz not null default now()
);
comment on table bank_tx is 'Giao dịch phát sinh của từng tài khoản ngân hàng.';
create index if not exists idx_bank_tx_acc on bank_tx (account_id, tx_date);

-- ---------------------------------------------------------------------
-- 4. CẤP QUYỀN + RLS cho các bảng mới
-- ---------------------------------------------------------------------
grant all on vat_carryover, bank_accounts, bank_tx to anon, authenticated, service_role;
grant all on all sequences in schema ketoan to anon, authenticated, service_role;

do $$
declare t text;
begin
  foreach t in array array['vat_carryover','bank_accounts','bank_tx'] loop
    if not exists (select 1 from pg_policies where schemaname='ketoan' and tablename=t) then
      execute format('alter table ketoan.%I enable row level security;', t);
      execute format($p$create policy %1$s_auth on ketoan.%1$I
        for all to authenticated using (true) with check (true);$p$, t);
    end if;
  end loop;
end $$;

-- =====================================================================
-- Xong. Sổ tiền mặt (cash_book) và sổ ngân hàng cũ (bank_book) vẫn còn
-- trong DB nhưng không dùng ở giao diện mới — không xóa để an toàn.
-- =====================================================================


-- ========== migration_tax_override.sql ==========

-- =====================================================================
-- MIGRATION: cho phép sửa tay tiền thuế / thành tiền trên từng dòng hóa đơn
-- Dùng khi database ĐÃ chạy schema.sql trước đó (không muốn làm lại từ đầu).
-- An toàn khi chạy nhiều lần.
-- Chạy trong Supabase > SQL Editor. (Mọi thứ nằm trong schema ketoan.)
-- =====================================================================

set search_path = ketoan, public;

-- 1. Thêm 2 cột ghi đè (nếu chưa có)
alter table ketoan.invoice_items
  add column if not exists amount_override numeric(18,2),
  add column if not exists tax_override    numeric(18,2);

-- ràng buộc không âm (bỏ qua nếu đã tồn tại)
do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'invoice_items_amount_override_chk') then
    alter table ketoan.invoice_items
      add constraint invoice_items_amount_override_chk
      check (amount_override is null or amount_override >= 0);
  end if;
  if not exists (select 1 from pg_constraint where conname = 'invoice_items_tax_override_chk') then
    alter table ketoan.invoice_items
      add constraint invoice_items_tax_override_chk
      check (tax_override is null or tax_override >= 0);
  end if;
end $$;

-- 2. Cập nhật trigger tính toán để ưu tiên số ghi đè
create or replace function ketoan.fn_item_compute()
returns trigger language plpgsql as $$
begin
  new.line_before_tax := coalesce(new.amount_override,
                                  round(new.quantity * new.unit_price, 2));
  new.line_tax        := coalesce(new.tax_override,
                                  round(new.line_before_tax * new.vat_rate / 100.0, 2));
  new.line_total      := new.line_before_tax + new.line_tax;
  return new;
end $$;

-- Trigger đã tồn tại từ schema.sql, trỏ sẵn tới hàm này nên không cần tạo lại.
-- (Nếu muốn chắc chắn, bỏ ghi chú 2 dòng dưới để tạo lại trigger.)
-- drop trigger if exists trg_item_compute on ketoan.invoice_items;
-- create trigger trg_item_compute before insert or update on ketoan.invoice_items
--   for each row execute function ketoan.fn_item_compute();

-- =====================================================================
-- Xong. Giờ mỗi dòng hóa đơn có thể để trống (tự tính) hoặc nhập tay
-- tiền thuế / thành tiền để khớp đúng hóa đơn nhà cung cấp.
-- =====================================================================


-- ========== migration_allow_negative.sql ==========

-- =====================================================================
-- CHO PHÉP SỐ ÂM trên dòng hóa đơn (phục vụ HÓA ĐƠN ĐIỀU CHỈNH giảm).
-- Hóa đơn điều chỉnh giảm có số lượng/tiền/thuế âm để trừ vào doanh thu, thuế.
-- Trước đây các cột này ràng buộc >= 0 nên bị chặn -> hóa đơn thành 0đ.
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

-- Gỡ MỌI ràng buộc check "không âm" trên invoice_items một cách chắc chắn.
-- Có nhiều biến thể tên (do inline check + migration trước), nên quét tự động
-- và bỏ những ràng buộc liên quan quantity / unit_price / amount_override / tax_override.
do $$
declare c record;
begin
  for c in
    select conname
    from pg_constraint con
    join pg_class t on t.oid = con.conrelid
    join pg_namespace n on n.oid = t.relnamespace
    where n.nspname = 'ketoan' and t.relname = 'invoice_items' and con.contype = 'c'
      and (
        conname like '%quantity%' or conname like '%unit_price%'
        or conname like '%amount_override%' or conname like '%tax_override%'
      )
  loop
    execute format('alter table ketoan.invoice_items drop constraint %I;', c.conname);
  end loop;
end $$;

-- =====================================================================
-- Xong. Giờ có thể ghi dòng hàng âm cho hóa đơn điều chỉnh.
-- Hóa đơn điều chỉnh đã import trước đó (đang hiện 0đ) cần XÓA rồi IMPORT LẠI
-- để lấy đúng số âm — vì lần trước chúng được tạo mà không có dòng hàng.
-- =====================================================================


-- ========== migration_cogs_cumulative.sql ==========

-- =====================================================================
-- SỬA GIÁ VỐN: tính bình quân gia quyền trên TOÀN BỘ hàng mua vào lũy kế
-- (từ trước đến hết kỳ), để hàng mua ở quý TRƯỚC bán ở quý NÀY vẫn có giá vốn.
-- Đồng thời thêm hàm reopen_period (mở lại kỳ đã chốt).
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

-- ---------------------------------------------------------------------
-- 1. close_period (Hướng 1 — lũy kế)
--    avg = (tồn đầu + MỌI hàng mua vào tới hết kỳ) / tổng số lượng
--    giá vốn = số lượng BÁN TRONG KỲ × avg
-- ---------------------------------------------------------------------
create or replace function close_period(p_year int, p_quarter int)
returns void language plpgsql
set search_path = ketoan, public as $$
declare
  m_start date := make_date(p_year, (p_quarter-1)*3 + 1, 1);
  m_end   date := (make_date(p_year, (p_quarter-1)*3 + 1, 1) + interval '3 months')::date;
begin
  if exists (select 1 from periods
             where year=p_year and quarter=p_quarter and status='closed') then
    raise exception 'Kỳ %/Q% đã được chốt.', p_year, p_quarter;
  end if;

  delete from cogs_period where year=p_year and quarter=p_quarter;

  insert into cogs_period(
    product_id, year, quarter,
    opening_qty, opening_value, purchase_qty, purchase_value,
    avg_unit_cost, sold_qty, cogs_value, closing_qty, closing_value)
  select
    p.id, p_year, p_quarter,
    coalesce(o.qty,0), coalesce(o.val,0),
    coalesce(pu.qty,0), coalesce(pu.val,0),
    -- đơn giá bình quân trên toàn bộ nguồn nhập lũy kế
    case when (coalesce(o.qty,0) + coalesce(pu.qty,0)) > 0
         then round((coalesce(o.val,0) + coalesce(pu.val,0))
                    / (coalesce(o.qty,0) + coalesce(pu.qty,0)), 4) else 0 end as avg_cost,
    coalesce(sa.qty,0),
    round(coalesce(sa.qty,0) * case when (coalesce(o.qty,0)+coalesce(pu.qty,0))>0
         then (coalesce(o.val,0)+coalesce(pu.val,0))
              /(coalesce(o.qty,0)+coalesce(pu.qty,0)) else 0 end, 2) as cogs,
    -- tồn cuối = toàn bộ nhập - toàn bộ bán (tới hết kỳ)
    (coalesce(o.qty,0) + coalesce(pu.qty,0) - coalesce(sa_all.qty,0)) as close_qty,
    round((coalesce(o.qty,0) + coalesce(pu.qty,0) - coalesce(sa_all.qty,0))
          * case when (coalesce(o.qty,0)+coalesce(pu.qty,0))>0
         then (coalesce(o.val,0)+coalesce(pu.val,0))
              /(coalesce(o.qty,0)+coalesce(pu.qty,0)) else 0 end, 2) as close_val
  from products p
  left join lateral (  -- tồn đầu kỳ: mọi khai báo tới hết kỳ này
    select sum(quantity) qty, sum(quantity*unit_cost) val
    from inventory_opening
    where product_id=p.id
      and (year < p_year or (year = p_year and quarter <= p_quarter))
  ) o on true
  left join lateral (  -- MUA vào LŨY KẾ: mọi hóa đơn mua tới hết kỳ
    select coalesce(sum(ii.quantity),0) qty,
           coalesce(sum(ii.line_before_tax),0) val
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='in'
      and i.invoice_date < m_end
  ) pu on true
  left join lateral (  -- BÁN trong kỳ (để tính giá vốn kỳ này)
    select coalesce(sum(ii.quantity),0) qty
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='out'
      and i.invoice_date >= m_start and i.invoice_date < m_end
  ) sa on true
  left join lateral (  -- BÁN lũy kế (để tính tồn cuối)
    select coalesce(sum(ii.quantity),0) qty
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='out'
      and i.invoice_date < m_end
  ) sa_all on true
  where p.kind='goods';

  insert into periods(year, quarter, status, closed_at)
  values (p_year, p_quarter, 'closed', now())
  on conflict (year, quarter)
  do update set status='closed', closed_at=now();
end $$;

-- ---------------------------------------------------------------------
-- 2. reopen_period — mở lại kỳ đã chốt (xóa kết quả giá vốn, bỏ khóa)
-- ---------------------------------------------------------------------
create or replace function reopen_period(p_year int, p_quarter int)
returns void language plpgsql
set search_path = ketoan, public as $$
begin
  delete from cogs_period where year=p_year and quarter=p_quarter;
  update periods set status='open', closed_at=null
    where year=p_year and quarter=p_quarter;
end $$;
comment on function reopen_period is 'Mở lại kỳ đã chốt để sửa dữ liệu rồi chốt lại.';

-- =====================================================================
-- Xong. Giá vốn giờ tính trên toàn bộ hàng mua vào (gồm quý trước).
-- =====================================================================


-- ========== migration_fix_close_period.sql ==========

-- =====================================================================
-- SỬA LỖI CHỐT KỲ: null value in column "opening_qty" ...
-- Nguyên nhân: sản phẩm KHÔNG có dòng tồn đầu kỳ -> lateral trả 0 dòng
-- -> o.qty / o.val thành NULL. Bọc coalesce(...,0) để luôn ra số.
-- Chạy trong Supabase > SQL Editor. An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

create or replace function close_period(p_year int, p_quarter int)
returns void language plpgsql
set search_path = ketoan, public as $$
declare
  m_start date := make_date(p_year, (p_quarter-1)*3 + 1, 1);
  m_end   date := (make_date(p_year, (p_quarter-1)*3 + 1, 1) + interval '3 months')::date;
begin
  if exists (select 1 from periods
             where year=p_year and quarter=p_quarter and status='closed') then
    raise exception 'Kỳ %/Q% đã được chốt.', p_year, p_quarter;
  end if;

  delete from cogs_period where year=p_year and quarter=p_quarter;

  insert into cogs_period(
    product_id, year, quarter,
    opening_qty, opening_value, purchase_qty, purchase_value,
    avg_unit_cost, sold_qty, cogs_value, closing_qty, closing_value)
  select
    p.id, p_year, p_quarter,
    coalesce(o.qty,0), coalesce(o.val,0),
    coalesce(pu.qty,0), coalesce(pu.val,0),
    case when (coalesce(o.qty,0) + coalesce(pu.qty,0)) > 0
         then round((coalesce(o.val,0) + coalesce(pu.val,0))
                    / (coalesce(o.qty,0) + coalesce(pu.qty,0)), 4) else 0 end,
    coalesce(sa.qty,0),
    round(coalesce(sa.qty,0) * case when (coalesce(o.qty,0)+coalesce(pu.qty,0))>0
         then (coalesce(o.val,0)+coalesce(pu.val,0))
              /(coalesce(o.qty,0)+coalesce(pu.qty,0)) else 0 end, 2),
    (coalesce(o.qty,0) + coalesce(pu.qty,0) - coalesce(sa.qty,0)),
    round((coalesce(o.qty,0) + coalesce(pu.qty,0) - coalesce(sa.qty,0))
          * case when (coalesce(o.qty,0)+coalesce(pu.qty,0))>0
         then (coalesce(o.val,0)+coalesce(pu.val,0))
              /(coalesce(o.qty,0)+coalesce(pu.qty,0)) else 0 end, 2)
  from products p
  left join lateral (
    select quantity qty, quantity*unit_cost val
    from inventory_opening
    where product_id=p.id and year=p_year and quarter=p_quarter
  ) o on true
  left join lateral (
    select coalesce(sum(ii.quantity),0) qty,
           coalesce(sum(ii.line_before_tax),0) val
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='in'
      and i.invoice_date >= m_start and i.invoice_date < m_end
  ) pu on true
  left join lateral (
    select coalesce(sum(ii.quantity),0) qty
    from invoice_items ii join invoices i on i.id=ii.invoice_id
    where ii.product_id=p.id and i.direction='out'
      and i.invoice_date >= m_start and i.invoice_date < m_end
  ) sa on true
  where p.kind='goods';

  insert into periods(year, quarter, status, closed_at)
  values (p_year, p_quarter, 'closed', now())
  on conflict (year, quarter)
  do update set status='closed', closed_at=now();
end $$;

-- =====================================================================
-- Xong. Chốt kỳ lại sẽ không còn lỗi null opening_qty.
-- =====================================================================


-- ========== migration_invoice_symbol.sql ==========

-- =====================================================================
-- SỬA LỖI MẤT HÓA ĐƠN: thêm cột ký hiệu + sửa ràng buộc chống trùng.
--
-- Vấn đề: số hóa đơn chỉ duy nhất TRONG MỘT KÝ HIỆU, không duy nhất toàn cục.
-- Ràng buộc cũ (chiều, đối tác, số HĐ) coi hai hóa đơn khác ký hiệu/ngày
-- cùng số (và cùng là Khách lẻ) là TRÙNG -> một cái bị từ chối, mất hóa đơn.
--
-- Sửa: thêm cột symbol (ký hiệu) và đổi ràng buộc thành
--      (chiều, số HĐ, ngày, ký hiệu) — không còn phụ thuộc đối tác.
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

-- 1. Thêm cột ký hiệu
alter table ketoan.invoices add column if not exists symbol text;

-- 2. Rút ký hiệu từ description cũ ("Ký hiệu XXX") cho dữ liệu đã có, nếu còn trống
update ketoan.invoices
set symbol = regexp_replace(description, '^Ký hiệu\s+', '')
where symbol is null and description like 'Ký hiệu %';

-- 3. Bỏ ràng buộc cũ (thiếu ký hiệu/ngày)
drop index if exists ketoan.uq_invoice_no_partner;

-- 4. Ràng buộc mới: duy nhất theo (chiều, ký hiệu, số HĐ, ngày).
--    Chỉ áp dụng khi có số HĐ. Hai hóa đơn khác ký hiệu/ngày/số -> không trùng.
--    coalesce để NULL ký hiệu không làm hỏng index.
create unique index if not exists uq_invoice_identity
  on ketoan.invoices (direction, coalesce(symbol,''), invoice_no, invoice_date)
  where invoice_no is not null;

-- =====================================================================
-- Xong. Giờ import lại file Q1: 16 hóa đơn ngày 27/02 (và các hóa đơn
-- khác bị mất do trùng số) sẽ ghi được vì ký hiệu/ngày khác nhau.
-- =====================================================================


-- ========== migration_bank_time.sql ==========

-- =====================================================================
-- MIGRATION: thêm thời điểm giao dịch (giờ:phút:giây) cho sổ ngân hàng
-- để sắp xếp đúng thứ tự các giao dịch TRONG CÙNG MỘT NGÀY.
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

-- tx_at: thời điểm đầy đủ. Nếu sao kê không có giờ, để NULL và dùng tx_date.
alter table ketoan.bank_tx
  add column if not exists tx_at timestamptz;

-- Với dữ liệu cũ chưa có giờ: gán tx_at = đầu ngày của tx_date để không vỡ thứ tự.
update ketoan.bank_tx set tx_at = tx_date::timestamptz where tx_at is null;

-- index theo tài khoản + thời điểm (phục vụ sắp xếp)
create index if not exists idx_bank_tx_acc_at on ketoan.bank_tx (account_id, tx_at);

-- =====================================================================
-- Xong. Giao dịch giờ sắp theo tx_at (ngày + giờ), hết âm sổ sai thứ tự.
-- =====================================================================


-- ========== migration_bank_counterparty.sql ==========

-- =====================================================================
-- Thêm cột "Tên tài khoản đối ứng" (Remitter's account name) cho sổ ngân hàng.
-- An toàn chạy nhiều lần.
-- =====================================================================

set search_path = ketoan, public;

alter table ketoan.bank_tx
  add column if not exists counterparty text;   -- tên TK đối ứng (người gửi/nhận)

-- =====================================================================
-- Xong.
-- =====================================================================


-- ========== migration_shopee_affiliate.sql ==========

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


-- ========== migration_pl_adjustments.sql ==========

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


-- ========== migration_expenses.sql ==========

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


-- ========== migration_aka.sql ==========

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

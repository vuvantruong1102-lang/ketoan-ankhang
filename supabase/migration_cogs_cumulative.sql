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

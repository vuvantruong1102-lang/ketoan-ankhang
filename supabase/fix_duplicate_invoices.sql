-- =====================================================================
-- DỌN HÓA ĐƠN TRÙNG (do import nhiều lần trước khi có cơ chế chặn trùng)
-- Trùng = cùng (chiều, đối tác, số hóa đơn). Giữ bản ghi CŨ NHẤT (id nhỏ nhất),
-- xóa các bản dư. Dòng hàng của bản bị xóa tự xóa theo (cascade).
--
-- CÁCH DÙNG: chạy BƯỚC 1 trước để xem sẽ xóa bao nhiêu. Nếu hợp lý, chạy BƯỚC 2.
-- =====================================================================

set search_path = ketoan, public;

-- ---------------------------------------------------------------------
-- BƯỚC 1 — CHỈ ĐẾM (không xóa gì). Chạy riêng dòng này trước.
-- ---------------------------------------------------------------------
select count(*) as so_ban_se_xoa
from ketoan.invoices a
where exists (
  select 1 from ketoan.invoices b
  where b.direction = a.direction
    and b.partner_id is not distinct from a.partner_id
    and b.invoice_no is not distinct from a.invoice_no
    and b.invoice_no is not null
    and b.id < a.id
);

-- (Tùy chọn) xem chi tiết các số hóa đơn bị trùng + số lần:
-- select invoice_no, direction, partner_id, count(*) so_lan
-- from ketoan.invoices
-- where invoice_no is not null
-- group by invoice_no, direction, partner_id
-- having count(*) > 1
-- order by so_lan desc;

-- ---------------------------------------------------------------------
-- BƯỚC 2 — XÓA bản trùng (giữ id nhỏ nhất). Chạy sau khi đã xem BƯỚC 1.
-- ---------------------------------------------------------------------
delete from ketoan.invoices a
using ketoan.invoices b
where a.direction = b.direction
  and a.partner_id is not distinct from b.partner_id
  and a.invoice_no is not distinct from b.invoice_no
  and a.invoice_no is not null
  and a.id > b.id;

-- =====================================================================
-- Xong. Chạy lại BƯỚC 1 để xác nhận còn 0 bản trùng.
-- Sau đó vào Báo cáo xem thuế đầu ra / doanh thu đã về đúng.
-- =====================================================================

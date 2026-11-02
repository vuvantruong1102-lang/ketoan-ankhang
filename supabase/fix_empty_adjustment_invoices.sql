-- =====================================================================
-- DỌN HÓA ĐƠN BÁN RA BỊ RỖNG (0đ, không có dòng hàng)
-- Đây là các hóa đơn điều chỉnh (số âm) đã import HỎNG trước khi cho phép số âm:
-- hóa đơn được tạo nhưng dòng hàng âm bị ràng buộc chặn -> thành 0đ.
-- Xóa chúng để IMPORT LẠI cho đúng số âm.
--
-- CHẠY SAU khi đã chạy migration_allow_negative.sql.
-- CÁCH DÙNG: chạy BƯỚC 1 (đếm) trước, rồi BƯỚC 2 (xóa).
-- =====================================================================

set search_path = ketoan, public;

-- ---------------------------------------------------------------------
-- BƯỚC 1 — ĐẾM số hóa đơn bán ra rỗng (không có dòng hàng). Chạy trước.
-- ---------------------------------------------------------------------
select count(*) as so_hoa_don_rong
from ketoan.invoices inv
where inv.direction = 'out'
  and not exists (
    select 1 from ketoan.invoice_items it where it.invoice_id = inv.id
  );

-- ---------------------------------------------------------------------
-- BƯỚC 2 — XÓA các hóa đơn rỗng đó. Chạy sau khi xem BƯỚC 1.
-- ---------------------------------------------------------------------
delete from ketoan.invoices inv
where inv.direction = 'out'
  and not exists (
    select 1 from ketoan.invoice_items it where it.invoice_id = inv.id
  );

-- =====================================================================
-- Xong. Giờ vào app: Hóa đơn > Import hóa đơn đầu ra > chọn lại file >
-- Ghi vào sổ. 220 hóa đơn điều chỉnh sẽ được ghi lại với số âm đúng,
-- và thuế đầu ra sẽ giảm về đúng (khớp tổng thuế trong file).
-- =====================================================================

-- =====================================================================
-- XÓA HÓA ĐƠN ĐÃ BỊ THAY THẾ (trạng thái "Hóa đơn đã bị thay thế" trong file)
--
-- Từ file quý 1: chỉ 1 hóa đơn bán ra bị thay thế:
--   Số 00000011, NGÀY 09/02/2026 (ký hiệu 1C26TVN).
--
-- LƯU Ý QUAN TRỌNG: có một hóa đơn KHÁC cũng mang số 00000011 nhưng
-- NGÀY 27/02/2026, trạng thái "Hóa đơn mới" — cái này HỢP LỆ, PHẢI GIỮ.
-- Vì vậy lệnh xóa khớp CẢ số HĐ LẪN ngày, không xóa theo số đơn thuần.
--
-- CÁCH DÙNG: chạy BƯỚC 1 (xem) trước, rồi BƯỚC 2 (xóa).
-- =====================================================================

set search_path = ketoan, public;

-- ---------------------------------------------------------------------
-- BƯỚC 1 — XEM hóa đơn sẽ xóa (phải đúng 1 dòng, ngày 2026-02-09). Chạy trước.
-- ---------------------------------------------------------------------
select id, invoice_no, invoice_date, direction,
       amount_before_tax, tax_amount, amount_total
from ketoan.invoices
where direction = 'out'
  and invoice_no = '00000011'
  and invoice_date = '2026-02-09';

-- (Đối chiếu: hóa đơn HỢP LỆ phải còn — chạy để chắc chắn KHÔNG đụng nó)
-- select id, invoice_no, invoice_date from ketoan.invoices
-- where direction='out' and invoice_no='00000011' and invoice_date='2026-02-27';

-- ---------------------------------------------------------------------
-- BƯỚC 2 — XÓA đúng hóa đơn bị thay thế. Chạy sau khi xem BƯỚC 1.
-- (Dòng hàng của hóa đơn này tự xóa theo nhờ on delete cascade.)
-- ---------------------------------------------------------------------
delete from ketoan.invoices
where direction = 'out'
  and invoice_no = '00000011'
  and invoice_date = '2026-02-09';

-- =====================================================================
-- Xong. Chạy lại BƯỚC 1 để xác nhận còn 0 dòng (đã xóa).
-- Hóa đơn hợp lệ cùng số nhưng ngày 27/02 vẫn còn nguyên.
-- =====================================================================

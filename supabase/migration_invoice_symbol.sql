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

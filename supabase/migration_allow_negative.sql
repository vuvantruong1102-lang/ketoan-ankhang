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

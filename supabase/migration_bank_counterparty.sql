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

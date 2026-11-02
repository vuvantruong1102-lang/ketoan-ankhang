# Phần mềm kế toán nội bộ (Thông tư 133/2016)

App kế toán nội bộ: hóa đơn đầu vào/ra, tồn kho, giá vốn, VAT, chi phí, lợi nhuận,
tài khoản ngân hàng, đối soát Shopee & AKA Media.

Stack: **React + Vite** · **Supabase (PostgreSQL)** · **Vercel**.

---

## CÀI ĐẶT CHO MỘT CÔNG TY MỚI (từ đầu)

### 1. Tạo project Supabase riêng
Mỗi công ty dùng **một project Supabase riêng** — dữ liệu tách biệt hoàn toàn.
- Vào https://supabase.com → New project (chọn region Singapore cho gần VN).

### 2. Tạo database
Vào **SQL Editor**, chạy **lần lượt 2 file** (trong thư mục `supabase/`):
1. `setup.sql` — tạo toàn bộ bảng, view, hàm (gộp sẵn mọi thứ, chạy một lần).
   Gặp hộp thoại cảnh báo RLS → bấm **Run without RLS**.
2. `schema_rls.sql` — cấp quyền + bật bảo mật.

Rồi **mở schema cho API**: Project Settings → API → **Exposed schemas** → thêm
`ketoan` → Save. (Thiếu bước này app báo lỗi "schema must be one of…".)

### 3. Tạo tài khoản đăng nhập
**Authentication → Users → Add user** (email + mật khẩu, bật *Auto Confirm*).
App không mở đăng ký công khai (dùng nội bộ).

### 4. Lấy khóa API
Supabase → **Project Settings → API**:
- Project URL → `VITE_SUPABASE_URL`
- anon public key → `VITE_SUPABASE_ANON_KEY`

### 5. Chạy thử ở máy
```bash
npm install
cp .env.example .env     # điền URL + anon key + tên công ty vào .env
npm run dev
```

### 6. Deploy lên Vercel
1. Đẩy code lên GitHub (repo riêng cho công ty này).
2. Vercel → New Project → chọn repo.
3. **Environment Variables**, thêm:
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
   - `VITE_APP_NAME` (tên công ty hiển thị trên app)
   - `VITE_OWN_TAX_CODE` (MST công ty — để kiểm hóa đơn đầu ra)
   - `VITE_OPENAI_API_KEY` (tùy chọn — để đọc hóa đơn PDF bằng AI)
4. Deploy. (`vercel.json` đã cấu hình sẵn rewrite cho React Router.)

---

## TÙY CHỈNH CHO CÔNG TY MỚI

Hầu hết tùy chỉnh làm qua **biến môi trường**, không cần sửa code:
- `VITE_APP_NAME`: tên app (sidebar + đăng nhập).
- `VITE_OWN_TAX_CODE`: MST công ty.
- Trang **Đối soát AKA Media**: tên nhà cung cấp lọc sửa được ngay trong app (ô "Lọc TK đối ứng").

Đổi tiêu đề tab trình duyệt: sửa `<title>` trong `index.html`.

---

## TÍNH NĂNG

- **Hóa đơn đầu vào / đầu ra**: nhập tay, import PDF/XML (AI), import Excel bảng kê.
- **Tồn kho**: tồn đầu kỳ, nhập/xuất từ hóa đơn, giá vốn bình quân gia quyền lũy kế.
- **Báo cáo**: Kết quả kinh doanh (quý/năm), Thuế VAT, chốt kỳ / mở lại kỳ.
- **Chi phí**: bán hàng, quản lý, loại khác — tự cộng vào lợi nhuận.
- **Tài khoản ngân hàng**: nhiều TK, số dư, import sao kê (AI).
- **Đối soát Shopee** và **Đối soát AKA Media**: panel độc lập.

---

## LƯU Ý

- `setup.sql` tạo mọi bảng trong schema **`ketoan`** (tách biệt `public`), nên nếu project
  Supabase này còn dùng cho app khác cũng không đụng nhau. Nhưng khuyến nghị: mỗi công ty
  một project riêng cho sạch.
- AI đọc hóa đơn (OpenAI) để key ở frontend — **phải đặt giới hạn chi tiêu** trong OpenAI
  dashboard. Không có key vẫn dùng app bình thường, chỉ mất tính năng đọc PDF.
- Đây là công cụ theo dõi nội bộ. Báo cáo nộp thuế vẫn nên đối chiếu với kế toán.

---

## CẤU TRÚC

```
supabase/
  setup.sql            # tạo toàn bộ database (chạy trước)
  schema_rls.sql       # cấp quyền + bật RLS (chạy sau)
  (các file migration_*.sql, fix_*.sql: lịch sử/tham khảo, KHÔNG cần chạy khi cài mới)
src/
  lib/                 # supabase client, auth, parser, định dạng
  components/           # Layout, UI, các modal import
  pages/                # các trang nghiệp vụ và báo cáo
```

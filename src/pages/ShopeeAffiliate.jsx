import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { Panel, Alert, Empty, Loading } from '../components/ui'
import { vnd, dmy } from '../lib/format'

const today = () => new Date().toISOString().slice(0, 10)

export default function ShopeeAffiliate() {
  const [rows, setRows] = useState(null)        // hoa hồng hàng ngày
  const [recs, setRecs] = useState(null)        // đối soát
  const [err, setErr] = useState('')
  // tìm tổng hoa hồng theo khoảng ngày
  const [searchRange, setSearchRange] = useState({ from: '', to: '' })

  // form hoa hồng hàng ngày
  const [f1, setF1] = useState({ tx_date: today(), amount: '', payment_code: '' })
  // form đối soát
  const [f3, setF3] = useState({
    reconcile_date: today(), period_from: '', period_to: '', shopee_amount: '',
  })

  async function load() {
    setErr('')
    const [{ data: a, error: e1 }, { data: r, error: e2 }] = await Promise.all([
      supabase.from('shopee_affiliate').select('*')
        .order('tx_date', { ascending: false }).order('id', { ascending: false }),
      supabase.from('shopee_reconcile').select('*')
        .order('reconcile_date', { ascending: false }).order('id', { ascending: false }),
    ])
    if (e1 || e2) setErr((e1 || e2).message)
    setRows(a || [])
    setRecs(r || [])
  }
  useEffect(() => { load() }, [])

  // ---- Hoa hồng hàng ngày ----
  async function addDaily() {
    setErr('')
    if (!f1.tx_date || !(Number(f1.amount) >= 0) || f1.amount === '') {
      setErr('Nhập ngày và số tiền hợp lệ.'); return
    }
    const { error } = await supabase.from('shopee_affiliate').insert({
      tx_date: f1.tx_date,
      amount: Number(f1.amount),
      payment_code: f1.payment_code.trim() || null,
    })
    if (error) { setErr(error.message); return }
    setF1({ tx_date: f1.tx_date, amount: '', payment_code: f1.payment_code })
    load()
  }
  async function delDaily(r) {
    if (!confirm(`Xóa hoa hồng ngày ${dmy(r.tx_date)}?`)) return
    await supabase.from('shopee_affiliate').delete().eq('id', r.id)
    load()
  }

  // tổng hoa hồng từ đầu đến nay
  const grandTotal = (rows || []).reduce((s, r) => s + Number(r.amount), 0)

  function sumInRange(from, to) {
    if (!from || !to) return 0
    return (rows || []).reduce((s, r) =>
      (r.tx_date >= from && r.tx_date <= to) ? s + Number(r.amount) : s, 0)
  }
  const searchTotal = sumInRange(searchRange.from, searchRange.to)
  const f3MyTotal = sumInRange(f3.period_from, f3.period_to)
  const f3Diff = f3MyTotal - Number(f3.shopee_amount || 0)

  // ---- Đối soát ----
  async function addReconcile() {
    setErr('')
    if (!f3.period_from || !f3.period_to) { setErr('Chọn khoảng thời gian đối soát.'); return }
    if (f3.period_to < f3.period_from) { setErr('“Đến ngày” phải sau “Từ ngày”.'); return }
    if (f3.shopee_amount === '') { setErr('Nhập số tiền Shopee đối soát.'); return }
    const { error } = await supabase.from('shopee_reconcile').insert({
      reconcile_date: f3.reconcile_date,
      period_from: f3.period_from,
      period_to: f3.period_to,
      shopee_amount: Number(f3.shopee_amount),
      status: 'unpaid',
    })
    if (error) { setErr(error.message); return }
    setF3({ reconcile_date: today(), period_from: '', period_to: '', shopee_amount: '' })
    load()
  }
  async function delReconcile(r) {
    if (!confirm('Xóa dòng đối soát này?')) return
    await supabase.from('shopee_reconcile').delete().eq('id', r.id)
    load()
  }
  // đổi trạng thái thanh toán (lưu ngay)
  async function setStatus(r, status) {
    const { error } = await supabase.from('shopee_reconcile')
      .update({ status }).eq('id', r.id)
    if (error) { setErr(error.message); return }
    setRecs((rs) => rs.map((x) => (x.id === r.id ? { ...x, status } : x)))
  }
  // đổi ngày thanh toán (lưu ngay)
  async function setPaidDate(r, paid_date) {
    const val = paid_date || null
    const { error } = await supabase.from('shopee_reconcile')
      .update({ paid_date: val }).eq('id', r.id)
    if (error) { setErr(error.message); return }
    setRecs((rs) => rs.map((x) => (x.id === r.id ? { ...x, paid_date: val } : x)))
  }
  // Shopee TT cả VAT (nhập tay, lưu ngay). Lưu trong recs dưới dạng chuỗi nháp
  // để gõ mượt; chỉ ghi DB khi rời ô (onBlur).
  function editVat(r, raw) {
    setRecs((rs) => rs.map((x) => (x.id === r.id ? { ...x, _vatDraft: raw } : x)))
  }
  async function saveVat(r) {
    const raw = r._vatDraft
    if (raw === undefined) return
    const val = raw === '' ? null : Number(raw)
    const { error } = await supabase.from('shopee_reconcile')
      .update({ shopee_amount_vat: val }).eq('id', r.id)
    if (error) { setErr(error.message); return }
    setRecs((rs) => rs.map((x) => (x.id === r.id
      ? { ...x, shopee_amount_vat: val, _vatDraft: undefined } : x)))
  }

  const loading = rows === null || recs === null

  return (
    <div className="full-bleed">
      <div className="page-head">
        <div>
          <h1>Đối soát Shopee Affiliate</h1>
          <div className="sub">Theo dõi hoa hồng affiliate hàng ngày và đối soát với số Shopee chi trả. Panel độc lập.</div>
        </div>
      </div>

      <Alert>{err}</Alert>

      {loading ? <Loading /> : (
        <div className="shopee-cols2">
          {/* ---------- HOA HỒNG HÀNG NGÀY ---------- */}
          <Panel title="1 · Hoa hồng hàng ngày">
            {/* tổng hoa hồng từ đầu đến nay — ngay dưới tiêu đề */}
            <div className="alert" style={{ background: 'var(--accent-soft)', color: 'var(--accent)' }}>
              Tổng hoa hồng đã nhận (từ đầu): <b>{vnd(grandTotal)}</b>
            </div>

            <div className="field">
              <label>Ngày</label>
              <input type="date" value={f1.tx_date}
                onChange={(e) => setF1({ ...f1, tx_date: e.target.value })} />
            </div>
            <div className="field">
              <label>Số tiền hoa hồng</label>
              <input type="number" step="any" min="0" value={f1.amount}
                onChange={(e) => setF1({ ...f1, amount: e.target.value })} />
            </div>
            <div className="field">
              <label>Mã thanh toán</label>
              <input placeholder="VD: PAY0001" value={f1.payment_code}
                onChange={(e) => setF1({ ...f1, payment_code: e.target.value })} />
            </div>
            <button className="btn accent sm" style={{ width: '100%' }} onClick={addDaily}>
              + Thêm ngày
            </button>

            {/* tìm tổng hoa hồng theo khoảng ngày */}
            <div className="row c2" style={{ marginTop: 14, marginBottom: 8 }}>
              <div className="field" style={{ marginBottom: 0 }}>
                <label>Tìm từ ngày</label>
                <input type="date" value={searchRange.from}
                  onChange={(e) => setSearchRange({ ...searchRange, from: e.target.value })} />
              </div>
              <div className="field" style={{ marginBottom: 0 }}>
                <label>Đến ngày</label>
                <input type="date" value={searchRange.to}
                  onChange={(e) => setSearchRange({ ...searchRange, to: e.target.value })} />
              </div>
            </div>
            {searchRange.from && searchRange.to && (
              <div className="alert" style={{ background: '#f7f9fb', color: 'var(--ink)', fontSize: 13 }}>
                Tổng hoa hồng trong khoảng: <b>{vnd(searchTotal)}</b>
              </div>
            )}

            <table className="grid" style={{ marginTop: 10 }}>
              <thead>
                <tr><th>Ngày</th><th className="num">Số tiền</th><th>Mã</th><th style={{ width: 28 }}></th></tr>
              </thead>
              <tbody>
                {rows.length === 0 ? (
                  <tr><td colSpan={4}><Empty>Chưa có dữ liệu.</Empty></td></tr>
                ) : rows.map((r) => (
                  <tr key={r.id}>
                    <td>{dmy(r.tx_date)}</td>
                    <td className="num">{vnd(r.amount)}</td>
                    <td>{r.payment_code || <span className="muted">—</span>}</td>
                    <td><button className="icon-btn del" onClick={() => delDaily(r)}>✕</button></td>
                  </tr>
                ))}
              </tbody>
            </table>
          </Panel>

          {/* ---------- ĐỐI SOÁT VỚI SHOPEE ---------- */}
          <Panel title="2 · Đối soát với Shopee">
            <div className="row c2">
              <div className="field">
                <label>Ngày đối soát</label>
                <input type="date" value={f3.reconcile_date}
                  onChange={(e) => setF3({ ...f3, reconcile_date: e.target.value })} />
              </div>
              <div className="field">
                <label>Số tiền Shopee đối soát</label>
                <input type="number" step="any" value={f3.shopee_amount}
                  onChange={(e) => setF3({ ...f3, shopee_amount: e.target.value })} />
              </div>
            </div>
            <div className="row c2">
              <div className="field">
                <label>Từ ngày</label>
                <input type="date" value={f3.period_from}
                  onChange={(e) => setF3({ ...f3, period_from: e.target.value })} />
              </div>
              <div className="field">
                <label>Đến ngày</label>
                <input type="date" value={f3.period_to}
                  onChange={(e) => setF3({ ...f3, period_to: e.target.value })} />
              </div>
            </div>

            {/* xem trước chênh lệch trước khi lưu */}
            {f3.period_from && f3.period_to && (
              <div className="alert" style={{
                background: '#f7f9fb', color: 'var(--ink)', fontSize: 13,
              }}>
                Tổng bạn đã nhập trong khoảng: <b>{vnd(f3MyTotal)}</b><br />
                Chênh lệch: <b className={f3Diff === 0 ? 'pos' : 'neg'}>
                  {f3Diff > 0 ? '+' : ''}{vnd(f3Diff)}
                </b>
                {f3Diff !== 0 && <span className="muted"> (dương = bạn nhập nhiều hơn Shopee)</span>}
              </div>
            )}

            <button className="btn accent sm" style={{ width: '100%' }} onClick={addReconcile}>
              + Lưu đối soát
            </button>

            <table className="grid shopee-rec" style={{ marginTop: 14 }}>
              <thead>
                <tr>
                  <th style={{ width: 90 }}>Ngày ĐS</th>
                  <th style={{ width: 160, whiteSpace: 'nowrap' }}>Khoảng</th>
                  <th className="num">Hoa hồng</th>
                  <th className="num">Shopee TT</th>
                  <th className="num">Chênh</th>
                  <th className="num" style={{ width: 150 }}>Shopee TT cả VAT</th>
                  <th style={{ width: 120 }}>Trạng thái</th>
                  <th style={{ width: 120 }}>Ngày thanh toán</th>
                  <th style={{ width: 28 }}></th>
                </tr>
              </thead>
              <tbody>
                {recs.length === 0 ? (
                  <tr><td colSpan={9}><Empty>Chưa có đối soát.</Empty></td></tr>
                ) : recs.map((r) => {
                  const my = sumInRange(r.period_from, r.period_to)
                  const diff = my - Number(r.shopee_amount)
                  const paid = r.status === 'paid'
                  const vatVal = r._vatDraft !== undefined
                    ? r._vatDraft
                    : (r.shopee_amount_vat ?? '')
                  return (
                    <tr key={r.id}>
                      <td style={{ whiteSpace: 'nowrap' }}>{dmy(r.reconcile_date)}</td>
                      <td style={{ whiteSpace: 'nowrap' }}>
                        {dmy(r.period_from)} → {dmy(r.period_to)}
                      </td>
                      <td className="num" style={{ whiteSpace: 'nowrap' }}>{vnd(my)}</td>
                      <td className="num" style={{ whiteSpace: 'nowrap' }}>{vnd(r.shopee_amount)}</td>
                      <td className="num" style={{ whiteSpace: 'nowrap' }}>
                        <span className={diff === 0 ? 'pos' : 'neg'}>
                          {diff > 0 ? '+' : ''}{vnd(diff)}
                        </span>
                      </td>
                      <td>
                        <input type="number" step="any" value={vatVal}
                          placeholder="Nhập…"
                          style={{ textAlign: 'right' }}
                          onChange={(e) => editVat(r, e.target.value)}
                          onBlur={() => saveVat(r)} />
                      </td>
                      <td>
                        <select value={r.status || 'unpaid'}
                          onChange={(e) => setStatus(r, e.target.value)}
                          style={{
                            color: paid ? 'var(--accent)' : 'var(--danger, #c0392b)',
                            fontWeight: 600,
                          }}>
                          <option value="unpaid">Chưa thanh toán</option>
                          <option value="paid">Đã thanh toán</option>
                        </select>
                      </td>
                      <td>
                        <input type="date" value={r.paid_date || ''}
                          onChange={(e) => setPaidDate(r, e.target.value)} />
                      </td>
                      <td><button className="icon-btn del" onClick={() => delReconcile(r)}>✕</button></td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </Panel>
        </div>
      )}
    </div>
  )
}

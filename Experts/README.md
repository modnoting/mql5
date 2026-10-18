# MQL5 Expert Advisors (EA)

โฟลเดอร์สำหรับจัดเก็บและพัฒนาระบบซื้อขายอัตโนมัติ (Expert Advisors) สำหรับ MetaTrader 5 (MQL5)

---

## มาตรฐานการพัฒนา EA

ตามข้อกำหนดใน **Master Prompt**:
1. **Modular Architecture**:
   - `Input Parameters` — ตั้งค่าแยกเป็นหมวดหมู่ชัดเจน
   - `Market & Symbol Data` — ตรวจสอบ Digits, Point, Spread, Min/Max Lot, Lot Step
   - `Signal Engine` — กฎการเข้าเทรดแบบ Rule-Based หรือ Price Action ที่ทดสอบซ้ำได้
   - `Position Sizing & Risk Management` — คำนวณ Lot จากความเสี่ยง (% Equity / Balance / Fixed Risk)
   - `Trade Execution & Error Handling` — ตรวจสอบ Return Code (`MqlTradeResult`), Slippage, Requote
   - `Position Management` — Trailing Stop, Break-Even, Multi-stage TP/SL
2. **Order & Position Logic**:
   - แยกแยะระหว่าง `Position`, `Order` และ `Deal` ตามสถาปัตยกรรมของ MT5
   - ป้องกันการเปิดออเดอร์ซ้ำในแท่งเดียวกัน (Bar-based execution filter)
   - มีระบบ Magic Number เพื่อแยกแยะออเดอร์ของ EA แต่ละตัว
3. **Safety & Capital Preservation**:
   - Max Daily Loss Filter
   - Max Drawdown Filter
   - Max Spread Filter
   - Trading Session Filter

---

## ไฟล์และกลยุทธ์ปัจจุบัน

- `PriceAction_BOS_Volume.mq5` — กลยุทธ์ Break of Structure ยืนยันด้วย Volume
- `PriceAction_DoubleBottomTop_SRSR.mq5` — กลยุทธ์ Reversal ดับเบิ้ลท็อป / ดับเบิ้ลบอทท่อม ร่วมกับแนวรับแนวต้าน
- `PriceAction_TrendFollowing_Pullback.mq5` — กลยุทธ์ตามแนวโน้มและรอจังหวะ Pullback

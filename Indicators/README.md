# MQL5 Custom Indicators

โฟลเดอร์สำหรับจัดเก็บและพัฒนา Custom Indicators สำหรับ MetaTrader 5 (MQL5)

---

## มาตรฐานการพัฒนา Indicator

ตามข้อกำหนดใน **Master Prompt**:
1. **Indicator Buffers & Data Structure**: กำหนด Plot type, Buffer size, และ Indexing ให้ชัดเจน
2. **Non-Repainting Rule**: คำนวณสัญญาณจากแท่งเทียนที่ปิดแล้ว (Bar 1 ขึ้นไป) เพื่อป้องกันสัญญาณหลอกหรือการเปลี่ยนรูปย้อนหลัง
3. **Multi-Timeframe Support**: หากมีการดึงข้อมูลต่าง Timeframe ต้องจัดการการ Sync ของแท่งเทียนและไม่ใช้ข้อมูลอนาคต
4. **Performance & Memory**: ป้องกันการ Re-calculate ข้อมูลเดิมซ้ำซ้อนโดยใช้ `prev_calculated` และตรวจสอบ `rates_total` อย่างมีประสิทธิภาพ
5. **Clean Display**: จัดการ Graphical Objects ให้เป็นระเบียบ ลบ Object อัตโนมัติเมื่อ Unload indicator (`OnDeinit`)
6. **Alert System**: รองรับ Alert, Push Notification, หรือ Sound Alert โดยต้องมีระบบป้องกันการแจ้งเตือนซ้ำ (Alert Once per Bar)

---

## โครงสร้างโฟลเดอร์ที่แนะนำ

```
Indicators/
├── Trend/             # อินดิเคเตอร์ระบุทิศทางแนวโน้ม (EMA, Supertrend, etc.)
├── Momentum/          # อินดิเคเตอร์วัดแรงและจังหวะ (RSI, Stochastic, MACD, etc.)
├── PriceAction/       # เครื่องมือตรวจจับแท่งเทียนและโครงสร้างราคา (Pinbar, Engulfing, BOS, FVG)
└── Utilities/          # เครื่องมือช่วยแสดงผล (Dashboard, Session Box, Spread Monitor)
```

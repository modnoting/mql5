# MQL5 Forex Automated Trading & Quantitative Analysis

Repository สำหรับพัฒนาระบบเทรดอัตโนมัติ (EA), Technical Indicators, และเครื่องมือวิเคราะห์เชิงปริมาณสำหรับ MetaTrader 5 (MQL5)

---

## โครงสร้างโปรเจกต์ (Project Structure)

```
mql5/
├── Experts/           # Expert Advisors (EA) และระบบเทรดอัตโนมัติ
│   ├── Examples/      # ตัวอย่างระบบเทรดและโมเดลอ้างอิง
│   ├── Free Robots/   # หุ่นยนต์เทรดและกลยุทธ์ Candlestick + Indicators
│   └── README.md      # มาตรฐานและคู่มือพัฒนา EA
├── Indicators/        # Custom Indicators และเครื่องมือตรวจจับสัญญาณเทคนิค
│   └── README.md      # มาตรฐานและคู่มือพัฒนา Indicator
├── GIT_PROMPT.md      # ชุด Prompt สั่งงาน AI และคู่มือ Git Workflow
└── README.md          # เอกสารภาพรวมของโปรเจกต์
```

---

## การพัฒนาและการทำงานร่วมกันผ่าน Git

- ดูคำสั่งและ Prompt สำหรับจัดการ Git ได้ที่ [GIT_PROMPT.md](file:///d:/forex_by_ai/mql5/GIT_PROMPT.md)
- Branching Strategy:
  - `main`: โค้ดหลักที่ผ่านการตรวจสอบและทดสอบแล้ว
  - `dev`: สาขาสำหรับการทดสอบและพัฒนาต่อเนื่อง
  - `feature/*`: สาขาสำหรับการพัฒนาฟีเจอร์หรือกลยุทธ์ใหม่

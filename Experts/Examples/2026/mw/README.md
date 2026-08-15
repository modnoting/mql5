# Devilmod M&W Pattern EA v1.00

Expert Advisor สำหรับเทรด Forex ด้วยรูปแบบ **M (Double Top)** และ **W (Double Bottom)** พร้อมระบบยืนยันด้วย Momentum และ Trend Filters

## 🎯 คุณสมบัติหลัก

### ✅ Pattern Detection (ตรวจจับรูปแบบอัตโนมัติ)
- **M Pattern (Double Top)**: ตรวจจับจุดสูงสุดสองครั้งที่ใกล้เคียงกัน (tolerance 0.2% หรือ 10-20 pips)
- **W Pattern (Double Bottom)**: ตรวจจับจุดต่ำสุดสองครั้งที่ใกล้เคียงกัน
- **Neckline Detection**: หา Neckline อัตโนมัติและรอการทะลุเพื่อยืนยัน
- **Swing High/Low Detection**: ใช้ swing strength configurable (default 5 bars)

### ✅ Entry Modes (โหมดการเข้า 2 แบบ)
1. **Aggressive Mode**: เข้าทันทีเมื่อราคาปิดทะลุ Neckline
2. **Conservative Mode**: รอให้ราคากลับมา Retest Neckline ก่อนเข้า (winrate สูงกว่า)

### ✅ Momentum Confirmation (ยืนยันด้วย Momentum)
- **RSI Divergence**: ยอดที่ 2 ควรมี RSI อ่อนแรงกว่ายอดที่ 1
- **MACD Weakness**: MACD ที่ยอดที่ 2 ควรมีค่าน้อยกว่า (แสดงถึงแรงซื้อ/ขายที่อ่อนลง)
- **Rejection Candle**: ตรวจจับแท่งเทียน rejection (shooting star, hammer)
- ระบบจะผ่านถ้าได้อย่างน้อย 50% ของ checks ที่เปิดใช้งาน

### ✅ Risk Management (จัดการความเสี่ยง)
- **Position Sizing**: คำนวณ lot อัตโนมัติตาม % ความเสี่ยงต่อบัญชี (1-2% แนะนำ)
- **Stop Loss**: วางเหนือ/ใต้ extreme ของรูปแบบ + buffer (ATR หรือ pips)
- **Take Profit**: คำนวณจากความสูงของรูปแบบ × Risk:Reward Ratio
- **Configurable RR**: สามารถตั้งค่า Risk:Reward เป็น 1:1, 1:1.5, 1:2

### ✅ Time & Trend Filters (กรองเวลาและเทรนด์)
- **Local Time Filter**: ใช้เวลาท้องถิ่นของคอมพิวเตอร์ (ไม่ใช่ GMT)
- **Day of Week Filter**: หลีกเลี่ยงวันหยุดสุดสัปดาห์
- **MA50/MA200 Trend Filter**: เทรดเฉพาะในทิศทางของเทรนด์
  - M Pattern: ขายเฉพาะใน downtrend
  - W Pattern: ซื้อเฉพาะใน uptrend

### ✅ CSV Authentication (Optional)
- ระบบยืนยันตัวตนผ่าน Google Sheets CSV (MD5 Hash)
- สามารถปิดการใช้งานได้โดยเว้นว่างช่อง Password

## 📋 Input Parameters

### Authentication
- `CSV_Password`: รหัสผ่านสำหรับ authentication (เว้นว่างเพื่อปิด)

### Pattern Detection
- `PatternTolerance_Percent`: ความคลาดเคลื่อนที่ยอมรับได้ (0.2% default = 10-20 pips)
- `LookbackBars`: จำนวน bars ที่ย้อนหลังเพื่อสแกน (100 default)
- `SwingStrength`: จำนวน bars แต่ละด้านสำหรับ swing detection (5 default)
- `NecklineBreak_Percent`: threshold การทะลุ Neckline (0.3% default)
- `MinRetracement_Percent`: retracement ขั้นต่ำ (10% default)

### Entry Settings
- `EntryMode`: 
  - `Aggressive`: เข้าทันทีเมื่อทะลุ Neckline
  - `Conservative`: รอ Retest (แนะนำ)
- `RetestWaitBars`: จำนวน bars สูงสุดที่รอ retest (10 default)

### Risk Management
- `RiskPercent`: % ความเสี่ยงต่อ trade (1.0% default, ตั้งเป็น 0 เพื่อใช้ fixed lot)
- `RR_Ratio`: อัตราส่วน Risk:Reward (1.5 default)
- `SL_Buffer_Pips`: buffer สำหรับ SL (20 pips default)
- `Lots`: Lot คงที่ (ใช้เมื่อ RiskPercent = 0)
- `g_magic_number`: Magic number สำหรับระบุ EA (20260509 default)

### Confirmation Filters
- `UseRSIDivergence`: เปิด/ปิด RSI Divergence check (true แนะนำ)
- `UseMACDWeakness`: เปิด/ปิด MACD weakness check (true แนะนำ)
- `UseRejectionCandle`: เปิด/ปิด rejection candle check (false default)
- `UseTrendFilter`: เปิด/ปิด MA trend filter (true แนะนำ)

### Time Filters
- `UseHourTrade`: เปิด/ปิดการกรองเวลา (true แนะนำ)
- `StartHour`: ชั่วโมงเริ่มต้น (local time) - ตัวอย่าง: 15 สำหรับ 15:00
- `EndHour`: ชั่วโมงสิ้นสุด (local time) - ตัวอย่าง: 23 สำหรับ 23:00

## 🚀 วิธีใช้งาน

### การติดตั้ง
1. คัดลอกไฟล์ `Devilmod-M-W.mq5` ไปยัง folder: `MQL5/Experts/`
2. เปิด MetaEditor และ Compile (F7)
3. รีสตาร์ท MetaTrader 5
4. หา EA ใน Navigator -> Expert Advisors

### การตั้งค่าสำหรับผู้เริ่มต้น (Recommended Settings)

**สำหรับ Conservative Trading (Winrate สูง):**
```
EntryMode = Conservative
RiskPercent = 1.0%
RR_Ratio = 1.5
UseRSIDivergence = true
UseMACDWeakness = true
UseTrendFilter = true
```

**สำหรับ Aggressive Trading (Opportunities มากกว่า):**
```
EntryMode = Aggressive
RiskPercent = 1.5%
RR_Ratio = 2.0
UseRSIDivergence = true
UseMACDWeakness = false
UseTrendFilter = false
```

### การตั้งเวลาเทรด (Local Time)

**ตัวอย่างสำหรับประเทศไทย (GMT+7):**

**London Session (08:00-17:00 GMT = 15:00-00:00 เวลาไทย):**
```
UseHourTrade = true
StartHour = 15
EndHour = 24
```

**NY Session (13:00-22:00 GMT = 20:00-05:00 เวลาไทย):**
```
UseHourTrade = true
StartHour = 20
EndHour = 5
```

**ถ้าอยู่เวียดนาม (GMT+7 เหมือนกัน)** - ใช้ค่าเดียวกัน

**ถ้าอยู่สหรัฐอเมริกา Eastern Time (GMT-5):**
- London Session: StartHour = 3, EndHour = 12

### Timeframe ที่แนะนำ
- **H1 (1 Hour)**: Balance ระหว่างสัญญาณและความน่าเชื่อถือ ⭐ แนะนำ
- **H4 (4 Hour)**: น่าเชื่อถือสูงสุด แต่สัญญาณน้อย
- **M30 (30 Min)**: สัญญาณมากขึ้น แต่ false signals เยอะกว่า

### คู่เงินที่แนะนำ
- **Major Pairs**: EUR/USD, GBP/USD, USD/JPY (spread ต่ำ, liquidity สูง)
- **Cross Pairs**: EUR/GBP, GBP/JPY (volatility สูงกว่า)
- **หลีกเลี่ยง Exotic Pairs**: spread สูง, เคลื่อนไหวไม่สม่ำเสมอ

## 📊 ตัวอย่างการทำงาน

### M Pattern (Double Top) - SELL Signal
```
1. ราคาขึ้นทำ High ครั้งแรก (Peak 1)
2. ราคาลงมาทำ Neckline (Valley)
3. ราคาขึ้นไปทำ High ครั้งที่สอง (Peak 2) ≈ Peak 1 (ภายใน 0.2%)
4. ตรวจสอบ RSI Divergence: RSI ที่ Peak2 < RSI ที่ Peak1 ✓
5. ตรวจสอบ MACD: MACD ที่ Peak2 อ่อนแรงกว่า ✓
6. ราคาปิดหลุด Neckline ลงมา → สัญญาณ SELL
7. (Conservative mode) รอราคากลับมา retest Neckline
8. เข้า SELL:
   - SL: เหนือ Peak2 + 20 pips
   - TP: Neckline - (Pattern Height × 1.5)
```

### W Pattern (Double Bottom) - BUY Signal
```
1. ราคาลงทำ Low ครั้งแรก (Trough 1)
2. ราคาเด้งขึ้นทำ Neckline (Peak)
3. ราคาลงมาทำ Low ครั้งที่สอง (Trough 2) ≈ Trough 1 (ภายใน 0.2%)
4. ตรวจสอบ RSI Divergence: RSI ที่ Trough2 > RSI ที่ Trough1 ✓
5. ตรวจสอบ MACD: MACD ที่ Trough2 อ่อนแรงกว่า ✓
6. ราคาปิดทะลุ Neckline ขึ้นไป → สัญญาณ BUY
7. (Conservative mode) รอราคากลับมา retest Neckline
8. เข้า BUY:
   - SL: ใต้ Trough2 - 20 pips
   - TP: Neckline + (Pattern Height × 1.5)
```

## ⚙️ Technical Details

### Pattern Detection Algorithm
- ใช้ Swing High/Low detection แบบ symmetrical (5 bars each side)
- ตรวจสอบความใกล้เคียงของ peaks/troughs ด้วย percentage tolerance
- คำนวณ pattern height สำหรับ SL/TP
- ตรวจสอบ retracement ขั้นต่ำ (10%) เพื่อกรอง consolidation patterns

### Momentum Indicators
- **RSI(14)**: ตรวจจับ divergence ระหว่าง price peaks และ RSI
- **MACD(12,26,9)**: เปรียบเทียบ histogram ระหว่างจุดสูงสุด/ต่ำสุด
- **ATR(14)**: ใช้คำนวณ dynamic SL buffer

### Trend Filters
- **MA50**: Moving Average 50 periods
- **MA200**: Moving Average 200 periods
- Trend direction: ราคาอยู่เหนือ/ใต้ MA หรือ MA50 ข้าม MA200

## 📈 Performance Tips

### เพิ่ม Winrate
1. ใช้ **Conservative Entry Mode** (รอ retest)
2. เปิด **RSI Divergence** และ **MACD Weakness**
3. เปิด **Trend Filter** (เทรดตามเทรนด์เท่านั้น)
4. เทรดในช่วง **London-NY overlap** (volatility สูง)
5. ใช้ **Timeframe H1 หรือ H4**

### เพิ่มจำนวนสัญญาณ
1. ใช้ **Aggressive Entry Mode**
2. ลด **PatternTolerance_Percent** เป็น 0.3-0.5%
3. ปิด **Trend Filter** (แต่ระวัง counter-trend)
4. เพิ่ม **LookbackBars** เป็น 150-200
5. ใช้ **Timeframe M30**

### Money Management
- **Risk per trade**: ไม่เกิน 1-2% ของบัญชี
- **Maximum drawdown**: ไม่เกิน 20% ของบัญชี
- **Daily loss limit**: หยุดเทรดถ้าขาดทุนเกิน 5% ในวันนั้น
- **Lot sizing**: ให้ EA คำนวณอัตโนมัติ (ตั้ง RiskPercent)

## ⚠️ คำเตือนและข้อควรระวัง

1. **ทดสอบใน Strategy Tester ก่อน**: อย่ารีบใช้งานบัญชีจริง
2. **Backtest อย่างน้อย 3-6 เดือน**: ดูผลลัพธ์ใน different market conditions
3. **Forward test**: ทดสอบบัญชี demo อย่างน้อย 1 เดือน
4. **Pattern tolerance สำคัญ**: ถ้าตั้งกว้างเกินไป (>0.5%) จะเจอ false patterns
5. **News events**: หลีกเลี่ยงการเทรดช่วงประกาศข่าวสำคัญ
6. **Spread**: ตรวจสอบว่า spread ไม่กว้างเกินไป (ควร <20 pips สำหรับ major pairs)

## 🔧 Troubleshooting

### EA ไม่ทำงาน
- ตรวจสอบ AutoTrading เปิดอยู่ (ปุ่มสีเขียวบน toolbar)
- ตรวจสอบ "Allow DLL imports" และ "Allow WebRequest" ใน Tools -> Options -> Expert Advisors
- เพิ่ม URL ใน WebRequest allowed list: `https://docs.google.com`

### ไม่มีสัญญาณเลย
- ลด PatternTolerance_Percent เป็น 0.3-0.5%
- เพิ่ม LookbackBars เป็น 150
- ลด SwingStrength เป็น 3-4
- ปิด Confirmation Filters ชั่วคราวเพื่อดูว่าเจอ pattern หรือไม่

### สัญญาณเยอะแต่แพ้บ่อย
- เปิด **Trend Filter**
- เปลี่ยนเป็น **Conservative Entry Mode**
- เปิด **RSI Divergence** และ **MACD Weakness**
- เพิ่ม PatternTolerance_Percent ให้เข้มงวดขึ้น (ลดเป็น 0.15%)

### Authentication failed
- ตรวจสอบว่าเลขบัญชีและรหัสผ่านถูกต้อง
- ตรวจสอบการเชื่อมต่ออินเทอร์เน็ต
- เพิ่ม Google Sheets URL ใน allowed list
- ถ้าไม่ใช้ authentication ให้เว้นว่างช่อง CSV_Password

## 📝 Changelog

### Version 1.00 (May 9, 2026)
- ✅ Initial release
- ✅ M (Double Top) และ W (Double Bottom) pattern detection
- ✅ Aggressive และ Conservative entry modes
- ✅ RSI Divergence, MACD weakness, rejection candle confirmations
- ✅ Dynamic position sizing based on risk percentage
- ✅ Configurable Risk:Reward ratios
- ✅ MA50/MA200 trend filters
- ✅ Local time filters
- ✅ CSV authentication system
- ✅ Full logging and on-chart comments

## 📧 Support

สำหรับคำถามหรือปัญหาในการใช้งาน:
- 📖 อ่าน README.md และ COMPARISON_REPORT.md
- 🔍 ตรวจสอบ Experts log ใน MetaTrader 5
- 💬 ติดต่อผู้พัฒนาผ่าน MQL5 community

---

**Copyright © 2026 DevilMod. All rights reserved.**

**Disclaimer**: การเทรด Forex มีความเสี่ยง EA นี้เป็นเครื่องมือช่วยเหลือเท่านั้น ไม่รับประกันผลกำไร ผู้ใช้ต้องรับผิดชอบความเสี่ยงเอง

# SMC EA Testing Guide

## Quick Start - ทดสอบครั้งแรก

### 1. Compile EA
1. เปิด MetaEditor (F4 ใน MT5)
2. เปิดไฟล์ `ExpertSMC.mq5`
3. กด F7 หรือคลิก Compile
4. ตรวจสอบไม่มี errors

### 2. Setup Strategy Tester
1. กด Ctrl+R หรือ View → Strategy Tester
2. ตั้งค่าดังนี้:
   - **Expert Advisor**: ExpertSMC
   - **Symbol**: XAUUSD
   - **Period**: M5 (Entry Timeframe)
   - **Date**: 2026-01-01 ถึง 2026-05-12
   - **Model**: Every tick based on real ticks (แม่นยำสุด)
   - **Optimization**: ปิด (ทดสอบครั้งแรก)
   - **Visual Mode**: เปิด (เพื่อดูการเทรด)

### 3. Input Parameters สำหรับทดสอบครั้งแรก

**⚙️ Simplified Test Mode (แนะนำ)**
```
=== Timeframe Settings ===
HTF_Timeframe = H1
Entry_Timeframe = M15
Confirm_Timeframe = M5

=== Market Structure Settings ===
SwingStrength = 3
LookbackBars = 100

=== Order Block Settings ===
OB_RetestTolerance = 50.0
OB_MaxAge = 50
OB_RequireImbalance = false
OB_MinImpulseSize = 30

=== Trading Formula Settings ===
UseFormula1 = true
UseFormula2 = false
UseFormula3 = false
UseSimplifiedMode = true          ✓ เปิดนี้! (เทรดง่ายกว่า)
Formula1_RequireSweep = false     ✓ ปิด sweep requirement
Formula1_RequireCHOCH = false     ✓ ปิด CHOCH requirement

=== Entry Confirmation Settings ===
RequireEngulfing = false          ✓ ปิดเพื่อให้เข้าเทรดง่าย
RequireMiniBOS = false            ✓ ปิดเพื่อให้เข้าเทรดง่าย
MinADX = 15                       ✓ ลดลงเพื่อให้เข้าเทรดง่าย
UseSpreadFilter = false           ✓ ปิดใน backtest
MaxSpread = 30

=== Risk Management ===
RiskPercent = 2.0
RR_Ratio = 2.0
UseCompounding = true
MinLotSize = 0.01
MaxLotSize = 10.0
MaxPositions = 1

=== General Settings ===
MagicNumber = 100100
ShowVisualAids = true             ✓ เปิดเพื่อดูโซน SMC
EnableDebugLog = true             ✓ เปิดเพื่อดู log ละเอียด
```

### 4. เริ่มทดสอบ
1. กด Start
2. ดูใน **Experts** tab (Toolbox → Experts)
3. คุณจะเห็น log แบบนี้:

```
[HTF] New bar detected: 2026.01.02 00:00
[HTF] Swing Highs: 8 | Swing Lows: 7
[HTF] Market Structure: UPTREND
[HTF] BSL Zones: 5 | SSL Zones: 5
[HTF] ✓ Bullish CHOCH detected at 2625.50
[HTF] Valid Order Blocks: 3
[ENTRY] New bar detected: 2026.01.02 01:15
[ENTRY] Checking for trading signals...
[F1] Checking Formula 1 signals...
[F1] Using Simplified Mode
[F1] Bullish structure detected
[F1] Found valid Bullish OB at 2620.30
[F1] ✓ OB Retest confirmed
[CONFIRM] Checking entry confirmations for BUY
[CONFIRM] ✓ Price in Discount zone
[CONFIRM] ✓ ADX OK: 22.5
[CONFIRM] ✓✓ All confirmations passed!
[F1] ✓✓ Entry confirmed! Opening BUY order
✓ BUY order opened | Formula: F1_SIMPLE_BUY | Lot: 0.05 | SL: 2618.50 | TP: 2625.00
```

---

## Debug Log Symbols

- ✓ = Passed / Success
- ✗ = Failed / Not met
- [HTF] = Higher Timeframe updates
- [ENTRY] = Entry timeframe checks
- [F1]/[F2] = Formula 1/2
- [CONFIRM] = Entry confirmation checks

---

## Troubleshooting - ไม่มีออเดอร์เปิด

### ปัญหา 1: ไม่เห็น log เลย
**สาเหตุ**: `EnableDebugLog = false`  
**แก้ไข**: เปิด `EnableDebugLog = true`

### ปัญหา 2: เห็น log แต่ไม่มีออเดอร์
ดูใน Experts log ว่า condition ไหนไม่ผ่าน:

**A. ไม่มี swing highs/lows**
```
[HTF] Swing Highs: 0 | Swing Lows: 0
```
**แก้ไข**: 
- ลด `SwingStrength` เป็น 2
- เพิ่ม `LookbackBars` เป็น 200

**B. Structure เป็น RANGING**
```
[HTF] Market Structure: RANGING
```
**แก้ไข**: 
- เลือกช่วงเวลาที่มี trend ชัดเจน (เช่น มกราคม-กุมภาพันธ์ 2026)
- หรือปิด structure filter

**C. ไม่มี Order Blocks**
```
[HTF] Valid Order Blocks: 0
```
**แก้ไข**:
- ลด `OB_MinImpulseSize` เป็น 20
- ปิด `OB_RequireImbalance = false`
- เพิ่ม `OB_MaxAge` เป็น 100

**D. OB Retest ไม่เจอ**
```
[F1] ✗ OB Retest not detected
```
**แก้ไข**:
- เพิ่ม `OB_RetestTolerance` เป็น 70% หรือ 100%

**E. ADX ต่ำเกินไป**
```
[CONFIRM] ✗ ADX too low: 12.5 < 20
```
**แก้ไข**:
- ลด `MinADX` เป็น 10 หรือ 15

**F. Price ไม่อยู่ใน Premium/Discount zone**
```
[CONFIRM] ✗ Price in Premium zone
```
**แก้ไข**:
- ปิด `UseFiboFilter = false` (ในระหว่างทดสอบ)

**G. Engulfing/MiniBOS ไม่เจอ**
```
[CONFIRM] ✗ No engulfing pattern
```
**แก้ไข**:
- ปิด `RequireEngulfing = false`
- ปิด `RequireMiniBOS = false`

### ปัญหา 3: Outside Kill Zone
```
[ENTRY] ✗ Outside Kill Zone
```
**แก้ไข**:
- ปิด `UseFormula3 = false`
- หรือปิด `UseLondonKillZone = false`

---

## Testing Modes

### 🟢 Simplified Mode (แนะนำสำหรับทดสอบ)
- **เปิด**: `UseSimplifiedMode = true`
- **เงื่อนไข**: Structure + OB Retest เท่านั้น
- **ข้อดี**: เข้าเทรดง่าย, เหมาะกับการทดสอบ
- **ข้อเสีย**: สัญญาณเยอะกว่า, อาจมี false signals

### 🔴 Full Mode (สำหรับ live trading)
- **เปิด**: `UseSimplifiedMode = false`
- **เงื่อนไข**: Sweep + CHOCH + OB (ครบตาม plan)
- **ข้อดี**: Winrate สูงกว่า, false signals น้อย
- **ข้อเสีย**: สัญญาณน้อย, ต้องรอนาน

---

## Parameter Optimization

หลังจากทดสอบ Simplified Mode แล้ว ให้ optimize parameters:

### Phase 1: Structure Detection
```
SwingStrength: 2, 3, 4, 5
LookbackBars: 100, 150, 200
```

### Phase 2: Order Blocks
```
OB_RetestTolerance: 30, 50, 70, 100
OB_MinImpulseSize: 20, 30, 50
OB_MaxAge: 30, 50, 100
```

### Phase 3: Risk Management
```
RiskPercent: 1.0, 2.0, 3.0
RR_Ratio: 1.5, 2.0, 3.0
```

### Phase 4: Filters
เปิดทีละตัว:
1. `UseFiboFilter = true`
2. `MinADX = 20`
3. `RequireMiniBOS = true`
4. `RequireEngulfing = true`

---

## Expected Results (Simplified Mode)

### ✅ Minimum Targets
- **Trades**: อย่างน้อย 5-10 trades ใน 4 เดือน
- **Winrate**: 40%+ (simplified mode)
- **Average RR**: 1.5:1+
- **Max Drawdown**: <25%

### 🎯 Good Results
- **Trades**: 20-50 trades
- **Winrate**: 45-50%
- **Average RR**: 1.8:1+
- **Max Drawdown**: <20%
- **Profit Factor**: >1.3

---

## Visual Aids on Chart

เมื่อเปิด `ShowVisualAids = true` จะเห็น:

- **Dotted Blue Lines**: Swing Highs/Lows
- **Blue Rectangles**: Bullish Order Blocks
- **Red Rectangles**: Bearish Order Blocks
- **Light Blue/Pink**: Fair Value Gaps
- **Yellow Lines**: BSL/SSL (เหลือง = active, เทา = swept)
- **Gray Lines**: Premium/Equilibrium/Discount levels

---

## Next Steps

1. ✅ ทดสอบ Simplified Mode ก่อน
2. ดู log และปรับ parameters ที่ไม่ผ่าน
3. เมื่อได้ trades แล้ว ทดสอบ Full Mode
4. Optimize parameters
5. Forward test กับข้อมูล 2026-05-01 ถึง 2026-05-12
6. Live test กับ demo account

---

## Support

หากยังมีปัญหา:
1. Copy log ทั้งหมดจาก Experts tab
2. Screenshot chart พร้อม Visual Aids
3. ส่งมาเพื่อวิเคราะห์ต่อ

//+------------------------------------------------------------------+
//|              PriceAction_DoubleBottomTop_SRSR.mq5                  |
//|              Double Bottom/Top + Support/Resistance + Pin Bar     |
//+------------------------------------------------------------------+
#property copyright "PriceAction EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Trade Settings ==="
input double   LotSize          = 0.1;
input int      StopLoss         = 500;
input int      TakeProfit       = 1500;
input int      MagicNumber      = 333333;
input int      Slippage         = 3;
input int      MaxSpread        = 30;

input group "=== Support/Resistance Settings ==="
input int      SR_Lookback      = 50;         // Lookback for S/R levels
input int      SR_Tolerance     = 100;        // Tolerance for level match (points)
input int      SR_Touches       = 2;          // Min touches to confirm level

input group "=== Double Bottom/Top Settings ==="
input int      PatternLookback  = 30;         // Bars to find pattern
input double   PatternTolerance = 0.002;      // Tolerance for double top/bottom (0.2%)
input bool     RequireNeckline  = true;       // Wait for neckline break

input group "=== Pin Bar Settings ==="
input double   PinBarWickPercent    = 0.60;   // Wick must be > 60% of range
input double   PinBarBodyPercent    = 0.35;   // Body must be < 35% of range
input bool     RequirePinBar        = true;   // Require Pin Bar for entry

input group "=== Exit Settings ==="
input bool     UseTrailingStop  = true;
input int      TrailingStart    = 300;
input int      TrailingStep     = 100;
input bool     UseBreakeven     = true;
input int      BreakevenTrigger = 200;
input int      BreakevenOffset  = 50;

CTrade trade;
CPositionInfo pos;

datetime lastBarTime = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   Print("EA DoubleBottom/Top + S/R + PinBar initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   Comment("");
}

//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime t = iTime(_Symbol, PERIOD_CURRENT, 0);
   if(t != lastBarTime) { lastBarTime = t; return true; }
   return false;
}

//+------------------------------------------------------------------+
struct SRLevel
{
   double price;
   int touches;
   int type; // 1=support, -1= resistance
};

//+------------------------------------------------------------------+
SRLevel FindSRLevel(int direction, int lookback)
{
   SRLevel level;
   level.price = 0;
   level.touches = 0;
   level.type = direction;
   
   if(direction == 1) // Support
   {
      double lowest = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 1));
      int touches = 0;
      
      for(int i = 1; i <= lookback; i++)
      {
         double low = iLow(_Symbol, PERIOD_CURRENT, i);
         if(MathAbs(low - lowest) <= SR_Tolerance * _Point)
            touches++;
      }
      
      level.price = lowest;
      level.touches = touches;
   }
   else // Resistance
   {
      double highest = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 1));
      int touches = 0;
      
      for(int i = 1; i <= lookback; i++)
      {
         double high = iHigh(_Symbol, PERIOD_CURRENT, i);
         if(MathAbs(high - highest) <= SR_Tolerance * _Point)
            touches++;
      }
      
      level.price = highest;
      level.touches = touches;
   }
   
   return level;
}

//+------------------------------------------------------------------+
bool HasPinBarBullish(int shift)
{
   // Pin Bar ที่มีไส้ยาวเกิน 60% ของแท่ง + ตัวเล็กกว่า 35% = สัญญาณแข็งแกร่งมาก
   double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   
   double body = MathAbs(close - open);
   double totalRange = high - low;
   double lowerWick = MathMin(open, close) - low;
   double upperWick = high - MathMax(open, close);
   
   if(totalRange == 0) return false;
   
   // Bullish Pin Bar: ไส้ล่างยาว > 60%, ตัวเล็ก < 35%
   bool longLowerWick = (lowerWick / totalRange) >= PinBarWickPercent;
   bool smallBody = (body / totalRange) <= PinBarBodyPercent;
   bool closeInUpperHalf = close > (low + totalRange * 0.6);
   
   return longLowerWick && smallBody && closeInUpperHalf;
}

//+------------------------------------------------------------------+
bool HasPinBarBearish(int shift)
{
   // Pin Bar ที่มีไส้ยาวเกิน 60% ของแท่ง + ตัวเล็กกว่า 35% = สัญญาณแข็งแกร่งมาก
   double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   
   double body = MathAbs(close - open);
   double totalRange = high - low;
   double upperWick = high - MathMax(open, close);
   double lowerWick = MathMin(open, close) - low;
   
   if(totalRange == 0) return false;
   
   // Bearish Pin Bar: ไส้บนยาว > 60%, ตัวเล็ก < 35%
   bool longUpperWick = (upperWick / totalRange) >= PinBarWickPercent;
   bool smallBody = (body / totalRange) <= PinBarBodyPercent;
   bool closeInLowerHalf = close < (high - totalRange * 0.6);
   
   return longUpperWick && smallBody && closeInLowerHalf;
}

//+------------------------------------------------------------------+
bool IsBullishCandle(int shift)
{
   return iClose(_Symbol, PERIOD_CURRENT, shift) > iOpen(_Symbol, PERIOD_CURRENT, shift);
}

//+------------------------------------------------------------------+
bool IsBearishCandle(int shift)
{
   return iClose(_Symbol, PERIOD_CURRENT, shift) < iOpen(_Symbol, PERIOD_CURRENT, shift);
}

//+------------------------------------------------------------------+
bool DetectDoubleBottom(int lookback)
{
   // หา Double Bottom: ราคาแตะ Low 2 ครั้งใกล้เคียงกัน
   double lowest = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 1));
   
   int touchCount = 0;
   int firstTouchBar = -1;
   int secondTouchBar = -1;
   
   for(int i = 1; i <= lookback; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      if(MathAbs(low - lowest) <= PatternTolerance * lowest)
      {
         if(firstTouchBar == -1)
            firstTouchBar = i;
         else
         {
            secondTouchBar = i;
            break;
         }
      }
   }
   
   if(firstTouchBar == -1 || secondTouchBar == -1) return false;
   
   // ตรวจสอบว่ามี swing high ระหว่าง 2 จุด
   double midHigh = 0;
   for(int i = secondTouchBar + 1; i < firstTouchBar; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(high > midHigh) midHigh = high;
   }
   
   // Neckline = swing high ระหว่าง 2 bottom
   double neckline = midHigh;
   
   // ตรวจสอบ Neckline Break
   if(RequireNeckline)
   {
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(close1 <= neckline) return false;
      if(!IsBullishCandle(1)) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
bool DetectDoubleTop(int lookback)
{
   // หา Double Top: ราคาแตะ High 2 ครั้งใกล้เคียงกัน
   double highest = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 1));
   
   int touchCount = 0;
   int firstTouchBar = -1;
   int secondTouchBar = -1;
   
   for(int i = 1; i <= lookback; i++)
   {
      double high = iHigh(_Symbol, PERIOD_CURRENT, i);
      if(MathAbs(high - highest) <= PatternTolerance * highest)
      {
         if(firstTouchBar == -1)
            firstTouchBar = i;
         else
         {
            secondTouchBar = i;
            break;
         }
      }
   }
   
   if(firstTouchBar == -1 || secondTouchBar == -1) return false;
   
   // ตรวจสอบว่ามี swing low ระหว่าง 2 จุด
   double midLow = 999999;
   for(int i = secondTouchBar + 1; i < firstTouchBar; i++)
   {
      double low = iLow(_Symbol, PERIOD_CURRENT, i);
      if(low < midLow) midLow = low;
   }
   
   // Neckline = swing low ระหว่าง 2 top
   double neckline = midLow;
   
   // ตรวจสอบ Neckline Break
   if(RequireNeckline)
   {
      double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
      if(close1 >= neckline) return false;
      if(!IsBearishCandle(1)) return false;
   }
   
   return true;
}

//+------------------------------------------------------------------+
void ManagePositions()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber) continue;
      if(pos.Symbol() != _Symbol) continue;
      
      double openPrice = pos.PriceOpen();
      double currentPrice = pos.PriceCurrent();
      double sl = pos.StopLoss();
      double tp = pos.TakeProfit();
      ulong ticket = pos.Ticket();
      
      if(pos.PositionType() == POSITION_TYPE_BUY)
      {
         double profit = (currentPrice - openPrice) / _Point;
         
         if(UseBreakeven && profit >= BreakevenTrigger && sl < openPrice)
         {
            double newSL = openPrice + BreakevenOffset * _Point;
            trade.PositionModify(ticket, newSL, tp);
         }
         
         if(UseTrailingStop && profit >= TrailingStart)
         {
            double newSL = currentPrice - TrailingStep * _Point;
            if(newSL > sl && newSL > openPrice)
               trade.PositionModify(ticket, newSL, tp);
         }
      }
      else if(pos.PositionType() == POSITION_TYPE_SELL)
      {
         double profit = (openPrice - currentPrice) / _Point;
         
         if(UseBreakeven && profit >= BreakevenTrigger && (sl > openPrice || sl == 0))
         {
            double newSL = openPrice - BreakevenOffset * _Point;
            trade.PositionModify(ticket, newSL, tp);
         }
         
         if(UseTrailingStop && profit >= TrailingStart)
         {
            double newSL = currentPrice + TrailingStep * _Point;
            if(newSL < sl || sl == 0)
               trade.PositionModify(ticket, newSL, tp);
         }
      }
   }
}

//+------------------------------------------------------------------+
bool HasOpenPosition()
{
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      if(!pos.SelectByIndex(i)) continue;
      if(pos.Magic() != MagicNumber) continue;
      if(pos.Symbol() != _Symbol) continue;
      return true;
   }
   return false;
}

//+------------------------------------------------------------------+
void OnTick()
{
   ManagePositions();
   
   if(!IsNewBar()) return;
   if(HasOpenPosition()) return;
   
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpread) return;
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // Find S/R levels
   SRLevel support = FindSRLevel(1, SR_Lookback);
   SRLevel resistance = FindSRLevel(-1, SR_Lookback);
   
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   // ============================================
   // BUY SIGNAL: Double Bottom + Support + Pin Bar Bullish
   // ============================================
   bool atSupport = MathAbs(close1 - support.price) <= SR_Tolerance * _Point;
   bool supportConfirmed = support.touches >= SR_Touches;
   bool doubleBottom = DetectDoubleBottom(PatternLookback);
   bool pinBarBull = HasPinBarBullish(1);
   bool candleBull = IsBullishCandle(1);
   
   if(atSupport && supportConfirmed && doubleBottom)
   {
      bool entrySignal = false;
      
      if(RequirePinBar)
         entrySignal = pinBarBull;
      else
         entrySignal = candleBull;
      
      if(entrySignal)
      {
         double sl = ask - StopLoss * _Point;
         double tp = ask + TakeProfit * _Point;
         
         if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "DBT_Buy"))
            Print("BUY: Double Bottom + Support + PinBar | Touches=", support.touches);
      }
   }
   
   // ============================================
   // SELL SIGNAL: Double Top + Resistance + Pin Bar Bearish
   // ============================================
   bool atResistance = MathAbs(close1 - resistance.price) <= SR_Tolerance * _Point;
   bool resistanceConfirmed = resistance.touches >= SR_Touches;
   bool doubleTop = DetectDoubleTop(PatternLookback);
   bool pinBarBear = HasPinBarBearish(1);
   bool candleBear = IsBearishCandle(1);
   
   if(atResistance && resistanceConfirmed && doubleTop)
   {
      bool entrySignal = false;
      
      if(RequirePinBar)
         entrySignal = pinBarBear;
      else
         entrySignal = candleBear;
      
      if(entrySignal)
      {
         double sl = bid + StopLoss * _Point;
         double tp = bid - TakeProfit * _Point;
         
         if(trade.Sell(LotSize, _Symbol, bid, sl, tp, "DBT_Sell"))
            Print("SELL: Double Top + Resistance + PinBar | Touches=", resistance.touches);
      }
   }
   
   // Comment
   Comment("DoubleBottom/Top EA | Support: ", DoubleToString(support.price, _Digits), 
           " (", support.touches, " touches) | Resistance: ", DoubleToString(resistance.price, _Digits),
           " (", resistance.touches, " touches)");
}
//+------------------------------------------------------------------+

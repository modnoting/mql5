//+------------------------------------------------------------------+
//|                     PriceAction_BOS_Volume.mq5                     |
//|                     Break of Structure + Volume Confirmation       |
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
input int      MagicNumber      = 222222;
input int      Slippage         = 3;
input int      MaxSpread        = 30;

input group "=== BOS Settings ==="
input int      SwingLookback    = 5;          // Bars to find swing points
input int      StructureBars    = 3;          // Bars to confirm structure
input bool     RequireRetest    = true;       // Wait for retest after BOS

input group "=== Volume Settings ==="
input double   VolumeMultiplier = 1.5;        // Volume must be X times average
input int      VolumeAvgPeriod  = 20;         // Volume average period
input bool     UseVolumeFilter  = true;       // Enable volume filter

input group "=== Candle Confirmation ==="
input bool     WaitCandleClose  = true;       // MUST wait for candle close
input double   MinBodyPercent   = 0.5;        // Min body/range ratio
input bool     RequireEngulfing = false;      // Require engulfing pattern

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
double prevSwingHigh = 0;
double prevSwingLow = 0;

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   Print("EA BOS+Volume initialized - WAIT FOR CANDLE CLOSE!");
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
double GetAverageVolume(int period)
{
   double sum = 0;
   for(int i = 1; i <= period; i++)
      sum += (double)iVolume(_Symbol, PERIOD_CURRENT, i);
   return sum / period;
}

//+------------------------------------------------------------------+
bool IsVolumeAboveAverage()
{
   if(!UseVolumeFilter) return true;
   
   double avgVol = GetAverageVolume(VolumeAvgPeriod);
   double currentVol = (double)iVolume(_Symbol, PERIOD_CURRENT, 1);
   
   return currentVol >= avgVol * VolumeMultiplier;
}

//+------------------------------------------------------------------+
double FindSwingHigh(int lookback)
{
   int idx = iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 1);
   return iHigh(_Symbol, PERIOD_CURRENT, idx);
}

//+------------------------------------------------------------------+
double FindSwingLow(int lookback)
{
   int idx = iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 1);
   return iLow(_Symbol, PERIOD_CURRENT, idx);
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
bool HasStrongBody(int shift)
{
   double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   
   double body = MathAbs(close - open);
   double range = high - low;
   
   if(range == 0) return false;
   return (body / range) >= MinBodyPercent;
}

//+------------------------------------------------------------------+
bool HasBullishEngulfing(int shift)
{
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   double o2 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   return (c2 < o2) && (c1 > o1) && (o1 <= c2) && (c1 >= o2);
}

//+------------------------------------------------------------------+
bool HasBearishEngulfing(int shift)
{
   double o1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double c1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   double o2 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double c2 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   return (c2 > o2) && (c1 < o1) && (o1 >= c2) && (c1 <= o2);
}

//+------------------------------------------------------------------+
bool CheckBullishBOS()
{
   // Find previous swing high
   double swingHigh = FindSwingHigh(SwingLookback + 10);
   
   // Current close must break above swing high
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(close1 <= swingHigh) return false;
   
   // Candle must be bullish and strong
   if(!IsBullishCandle(1)) return false;
   if(!HasStrongBody(1)) return false;
   
   // Volume confirmation
   if(!IsVolumeAboveAverage()) return false;
   
   // Optional: Require engulfing
   if(RequireEngulfing && !HasBullishEngulfing(1)) return false;
   
   return true;
}

//+------------------------------------------------------------------+
bool CheckBearishBOS()
{
   // Find previous swing low
   double swingLow = FindSwingLow(SwingLookback + 10);
   
   // Current close must break below swing low
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   if(close1 >= swingLow) return false;
   
   // Candle must be bearish and strong
   if(!IsBearishCandle(1)) return false;
   if(!HasStrongBody(1)) return false;
   
   // Volume confirmation
   if(!IsVolumeAboveAverage()) return false;
   
   // Optional: Require engulfing
   if(RequireEngulfing && !HasBearishEngulfing(1)) return false;
   
   return true;
}

//+------------------------------------------------------------------+
bool CheckBullishRetest()
{
   // After BOS, wait for pullback and bullish confirmation
   double swingHigh = FindSwingHigh(SwingLookback + 10);
   
   // Price pulled back to broken level
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   // Pullback zone: near the broken resistance (now support)
   double tolerance = 100 * _Point;
   bool inRetestZone = MathAbs(low1 - swingHigh) <= tolerance;
   
   // Bullish confirmation candle
   bool bullishCandle = IsBullishCandle(1) && HasStrongBody(1);
   
   return inRetestZone && bullishCandle;
}

//+------------------------------------------------------------------+
bool CheckBearishRetest()
{
   // After BOS, wait for pullback and bearish confirmation
   double swingLow = FindSwingLow(SwingLookback + 10);
   
   // Price pulled back to broken level
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 1);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   // Pullback zone: near the broken support (now resistance)
   double tolerance = 100 * _Point;
   bool inRetestZone = MathAbs(high1 - swingLow) <= tolerance;
   
   // Bearish confirmation candle
   bool bearishCandle = IsBearishCandle(1) && HasStrongBody(1);
   
   return inRetestZone && bearishCandle;
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
   
   // COMMENT: Show warning
   Comment("BOS+Volume EA | WARNING: Wait for candle close! | Spread: ", (int)spread);
   
   // ============================================
   // BUY SIGNAL: Bullish BOS + Volume + Candle Confirm
   // ============================================
   if(CheckBullishBOS())
   {
      double sl = ask - StopLoss * _Point;
      double tp = ask + TakeProfit * _Point;
      
      if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "BOS_Buy"))
         Print("BUY: Bullish BOS confirmed | Volume OK | Candle closed");
   }
   
   // Retest entry
   if(RequireRetest && CheckBullishRetest())
   {
      double sl = ask - StopLoss * _Point;
      double tp = ask + TakeProfit * _Point;
      
      if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "BOS_Retest_Buy"))
         Print("BUY: Bullish BOS Retest | Support confirmed");
   }
   
   // ============================================
   // SELL SIGNAL: Bearish BOS + Volume + Candle Confirm
   // ============================================
   if(CheckBearishBOS())
   {
      double sl = bid + StopLoss * _Point;
      double tp = bid - TakeProfit * _Point;
      
      if(trade.Sell(LotSize, _Symbol, bid, sl, tp, "BOS_Sell"))
         Print("SELL: Bearish BOS confirmed | Volume OK | Candle closed");
   }
   
   // Retest entry
   if(RequireRetest && CheckBearishRetest())
   {
      double sl = bid + StopLoss * _Point;
      double tp = bid - TakeProfit * _Point;
      
      if(trade.Sell(LotSize, _Symbol, bid, sl, tp, "BOS_Retest_Sell"))
         Print("SELL: Bearish BOS Retest | Resistance confirmed");
   }
}
//+------------------------------------------------------------------+

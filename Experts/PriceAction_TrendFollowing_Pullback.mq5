//+------------------------------------------------------------------+
//|                           PriceAction_TrendFollowing_Pullback.mq5 |
//|                           Trend Following + Pullback to Key Level |
//+------------------------------------------------------------------+
#property copyright "PriceAction EA"
#property link      ""
#property version   "1.00"
#property strict

#include <Trade\Trade.mqh>
#include <Trade\PositionInfo.mqh>

input group "=== Trade Settings ==="
input double   LotSize          = 0.1;
input int      StopLoss         = 500;        // SL (points)
input int      TakeProfit       = 1500;       // TP (points)
input int      MagicNumber      = 111111;
input int      Slippage         = 3;
input int      MaxSpread        = 30;         // Max Spread (points)

input group "=== Trend Settings ==="
input int      EMA_Fast         = 20;
input int      EMA_Slow         = 50;
input int      ATR_Period       = 14;
input double   ATR_Multiplier   = 1.5;        // Pullback threshold

input group "=== Key Level Settings ==="
input int      SR_Lookback      = 50;         // Support/Resistance lookback
input int      SR_Tolerance     = 100;        // Tolerance for level match (points)

input group "=== Exit Settings ==="
input bool     UseTrailingStop  = true;
input int      TrailingStart    = 300;
input int      TrailingStep     = 100;
input bool     UseBreakeven     = true;
input int      BreakevenTrigger = 200;
input int      BreakevenOffset  = 50;

CTrade trade;
CPositionInfo pos;

int emaFastHandle, emaSlowHandle, atrHandle;
double emaFastBuf[], emaSlowBuf[], atrBuf[];

datetime lastBarTime = 0;
int prevTrend = 0; // 0=none, 1=uptrend, -1=downtrend

//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(MagicNumber);
   trade.SetDeviationInPoints(Slippage);
   
   emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   atrHandle = iATR(_Symbol, PERIOD_CURRENT, ATR_Period);
   
   if(emaFastHandle == INVALID_HANDLE || emaSlowHandle == INVALID_HANDLE || atrHandle == INVALID_HANDLE)
   {
      Print("Failed to create indicators");
      return(INIT_FAILED);
   }
   
   ArraySetAsSeries(emaFastBuf, true);
   ArraySetAsSeries(emaSlowBuf, true);
   ArraySetAsSeries(atrBuf, true);
   
   Print("EA TrendFollowing+Pullback initialized");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if(emaFastHandle != INVALID_HANDLE) IndicatorRelease(emaFastHandle);
   if(emaSlowHandle != INVALID_HANDLE) IndicatorRelease(emaSlowHandle);
   if(atrHandle != INVALID_HANDLE) IndicatorRelease(atrHandle);
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
int DetectTrend()
{
   if(CopyBuffer(emaFastHandle, 0, 0, 3, emaFastBuf) < 3) return 0;
   if(CopyBuffer(emaSlowHandle, 0, 0, 3, emaSlowBuf) < 3) return 0;
   
   // EMA crossover check
   if(emaFastBuf[1] > emaSlowBuf[1] && emaFastBuf[2] <= emaSlowBuf[2]) return 1;  // Bullish cross
   if(emaFastBuf[1] < emaSlowBuf[1] && emaFastBuf[2] >= emaSlowBuf[2]) return -1; // Bearish cross
   
   // Current state
   if(emaFastBuf[1] > emaSlowBuf[1]) return 1;
   if(emaFastBuf[1] < emaSlowBuf[1]) return -1;
   
   return 0;
}

//+------------------------------------------------------------------+
double FindSupportLevel(int lookback)
{
   double lowest = iLow(_Symbol, PERIOD_CURRENT, iLowest(_Symbol, PERIOD_CURRENT, MODE_LOW, lookback, 1));
   return lowest;
}

//+------------------------------------------------------------------+
double FindResistanceLevel(int lookback)
{
   double highest = iHigh(_Symbol, PERIOD_CURRENT, iHighest(_Symbol, PERIOD_CURRENT, MODE_HIGH, lookback, 1));
   return highest;
}

//+------------------------------------------------------------------+
bool IsPullbackToSupport(double price, double support, double tolerance)
{
   return MathAbs(price - support) <= tolerance * _Point;
}

//+------------------------------------------------------------------+
bool IsPullbackToResistance(double price, double resistance, double tolerance)
{
   return MathAbs(price - resistance) <= tolerance * _Point;
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
bool HasPinBarBullish(int shift)
{
   double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   
   double body = MathAbs(close - open);
   double totalRange = high - low;
   double lowerWick = MathMin(open, close) - low;
   
   if(totalRange == 0) return false;
   
   // Bullish pin bar: long lower wick, small body at top
   return (lowerWick / totalRange > 0.6) && (body / totalRange < 0.35);
}

//+------------------------------------------------------------------+
bool HasPinBarBearish(int shift)
{
   double open = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close = iClose(_Symbol, PERIOD_CURRENT, shift);
   double high = iHigh(_Symbol, PERIOD_CURRENT, shift);
   double low = iLow(_Symbol, PERIOD_CURRENT, shift);
   
   double body = MathAbs(close - open);
   double totalRange = high - low;
   double upperWick = high - MathMax(open, close);
   
   if(totalRange == 0) return false;
   
   // Bearish pin bar: long upper wick, small body at bottom
   return (upperWick / totalRange > 0.6) && (body / totalRange < 0.35);
}

//+------------------------------------------------------------------+
bool HasEngulfingBullish(int shift)
{
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   // Previous bearish, current bullish engulfing
   return (close2 < open2) && (close1 > open1) && 
          (open1 <= close2) && (close1 >= open2);
}

//+------------------------------------------------------------------+
bool HasEngulfingBearish(int shift)
{
   double open1 = iOpen(_Symbol, PERIOD_CURRENT, shift);
   double close1 = iClose(_Symbol, PERIOD_CURRENT, shift);
   double open2 = iOpen(_Symbol, PERIOD_CURRENT, shift + 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, shift + 1);
   
   // Previous bullish, current bearish engulfing
   return (close2 > open2) && (close1 < open1) && 
          (open1 >= close2) && (close1 <= open2);
}

//+------------------------------------------------------------------+
bool CheckBOSBullish()
{
   // Break of Structure: price breaks above recent high
   double high1 = iHigh(_Symbol, PERIOD_CURRENT, 2);
   double high2 = iHigh(_Symbol, PERIOD_CURRENT, 3);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   return close > high1 && high1 > high2;
}

//+------------------------------------------------------------------+
bool CheckBOSBearish()
{
   // Break of Structure: price breaks below recent low
   double low1 = iLow(_Symbol, PERIOD_CURRENT, 2);
   double low2 = iLow(_Symbol, PERIOD_CURRENT, 3);
   double close = iClose(_Symbol, PERIOD_CURRENT, 1);
   
   return close < low1 && low1 < low2;
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
         
         // Breakeven
         if(UseBreakeven && profit >= BreakevenTrigger && sl < openPrice)
         {
            double newSL = openPrice + BreakevenOffset * _Point;
            trade.PositionModify(ticket, newSL, tp);
         }
         
         // Trailing Stop
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
         
         // Breakeven
         if(UseBreakeven && profit >= BreakevenTrigger && (sl > openPrice || sl == 0))
         {
            double newSL = openPrice - BreakevenOffset * _Point;
            trade.PositionModify(ticket, newSL, tp);
         }
         
         // Trailing Stop
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
   
   // Check spread
   long spread = SymbolInfoInteger(_Symbol, SYMBOL_SPREAD);
   if(spread > MaxSpread) return;
   
   // Get indicator values
   if(CopyBuffer(atrHandle, 0, 0, 3, atrBuf) < 3) return;
   
   int trend = DetectTrend();
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double support = FindSupportLevel(SR_Lookback);
   double resistance = FindResistanceLevel(SR_Lookback);
   
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   
   // BUY SIGNAL: Uptrend + Pullback to Support + Bullish Confirmation
   if(trend == 1 || (emaFastBuf[1] > emaSlowBuf[1]))
   {
      if(IsPullbackToSupport(close1, support, SR_Tolerance))
      {
         bool candleConfirm = IsBullishCandle(1) || HasPinBarBullish(1) || HasEngulfingBullish(1);
         bool bosConfirm = CheckBOSBullish();
         
         if(candleConfirm || bosConfirm)
         {
            double sl = ask - StopLoss * _Point;
            double tp = ask + TakeProfit * _Point;
            
            if(trade.Buy(LotSize, _Symbol, ask, sl, tp, "TrendFollow_Buy"))
               Print("BUY: Trend+Pullback | SL=", sl, " TP=", tp);
         }
      }
   }
   
   // SELL SIGNAL: Downtrend + Pullback to Resistance + Bearish Confirmation
   if(trend == -1 || (emaFastBuf[1] < emaSlowBuf[1]))
   {
      if(IsPullbackToResistance(close1, resistance, SR_Tolerance))
      {
         bool candleConfirm = IsBearishCandle(1) || HasPinBarBearish(1) || HasEngulfingBearish(1);
         bool bosConfirm = CheckBOSBearish();
         
         if(candleConfirm || bosConfirm)
         {
            double sl = bid + StopLoss * _Point;
            double tp = bid - TakeProfit * _Point;
            
            if(trade.Sell(LotSize, _Symbol, bid, sl, tp, "TrendFollow_Sell"))
               Print("SELL: Trend+Pullback | SL=", sl, " TP=", tp);
         }
      }
   }
}
//+------------------------------------------------------------------+

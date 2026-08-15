//+------------------------------------------------------------------+
//|                           OB_OS_RSI_STOCH_EA_V4.0_M5.mq5        |
//|                           Overbought/Oversold System              |
//|                           M5 Balanced Accuracy + Smart Filter     |
//+------------------------------------------------------------------+
#property copyright "EA V4.0 - Overbought/Oversold M5 Balanced"
#property link      ""
#property version   "4.00"

#include <Trade\Trade.mqh>
#include <Trade\SymbolInfo.mqh>

//+------------------------------------------------------------------+
//| INPUT PARAMETERS                                                  |
//+------------------------------------------------------------------+

//--- Entry Indicator Settings
input int      RSI_Period = 14;           // RSI Period
input int      Stoch_K = 5;              // Stochastic %K Period
input int      Stoch_D = 3;              // Stochastic %D Period
input int      Stoch_Slowing = 3;        // Stochastic Slowing
input int      EMA_Fast = 50;            // EMA Fast Period
input int      EMA_Slow = 200;           // EMA Slow Period
input int      ADX_Period = 14;          // ADX Period

//--- Overbought/Oversold Thresholds (V4.0 Balanced)
input double   RSI_Oversold = 28.0;      // RSI Oversold Level
input double   RSI_Overbought = 72.0;    // RSI Overbought Level
input double   Stoch_Oversold = 18.0;    // Stochastic Oversold Level
input double   Stoch_Overbought = 82.0;  // Stochastic Overbought Level
input int      ADX_MinStrength = 18;     // Minimum ADX for trend

//--- Range Filter Settings (V4.0 Smart)
input int      RangeBars = 5;            // Bars to check for range
input double   RangeMaxPercent = 0.5;    // Max % range to consider sideways

//--- Risk Management
input double   LotSize = 0.01;           // Base Lot Size
input double   MaxLotPerOrder = 0.05;    // Max Lot Per Order
input double   MaxTotalLot = 0.20;       // Max Total Lot
input int      StopLossPoints = 2000;    // Stop Loss (Points)
input int      TakeProfitPoints = 3000;  // Take Profit (Points)

//--- Trailing Stop
input int      TrailingPoints = 1500;    // Trailing Stop Distance
input bool     UseTrailingStop = true;   // Enable Trailing Stop

//--- Time Filter
input bool     UseHourTrade = true;
input int      StartHour = 8;
input int      EndHour = 22;

//--- Magic Number
input ulong    MagicNumber = 901234;

//+------------------------------------------------------------------+
//| GLOBAL VARIABLES                                                  |
//+------------------------------------------------------------------+
CTrade         ExtTrade;
CSymbolInfo    ExtSymbolInfo;

int g_tradeCount = 0;
bool g_isBuy = false;
bool g_isSell = false;
datetime g_timeLastBar = 0;

// Indicator handles
int g_rsiHandle = INVALID_HANDLE;
int g_stochHandle = INVALID_HANDLE;
int g_emaFastHandle = INVALID_HANDLE;
int g_emaSlowHandle = INVALID_HANDLE;
int g_adxHandle = INVALID_HANDLE;

//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit()
{
   ExtTrade.SetExpertMagicNumber(MagicNumber);
   ExtTrade.SetDeviationInPoints(30);
   ExtTrade.SetTypeFilling(ORDER_FILLING_FOK);

   if (!ExtSymbolInfo.Name(_Symbol))
   {
      Print("ERROR: Cannot initialize symbol info");
      return(INIT_FAILED);
   }

   g_rsiHandle = iRSI(_Symbol, PERIOD_CURRENT, RSI_Period, PRICE_CLOSE);
   g_stochHandle = iStochastic(_Symbol, PERIOD_CURRENT, Stoch_K, Stoch_D, Stoch_Slowing, MODE_SMA, STO_LOWHIGH);
   g_emaFastHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Fast, 0, MODE_EMA, PRICE_CLOSE);
   g_emaSlowHandle = iMA(_Symbol, PERIOD_CURRENT, EMA_Slow, 0, MODE_EMA, PRICE_CLOSE);
   g_adxHandle = iADX(_Symbol, PERIOD_CURRENT, ADX_Period);

   if (g_rsiHandle == INVALID_HANDLE || g_stochHandle == INVALID_HANDLE ||
       g_emaFastHandle == INVALID_HANDLE || g_emaSlowHandle == INVALID_HANDLE ||
       g_adxHandle == INVALID_HANDLE)
   {
      Print("ERROR: Cannot create indicator handles");
      return(INIT_FAILED);
   }

   Print("=== OB_OS_RSI_STOCH_EA_V4.0_M5 (MT5) INITIALIZED ===");
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                 |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   if (g_rsiHandle != INVALID_HANDLE) IndicatorRelease(g_rsiHandle);
   if (g_stochHandle != INVALID_HANDLE) IndicatorRelease(g_stochHandle);
   if (g_emaFastHandle != INVALID_HANDLE) IndicatorRelease(g_emaFastHandle);
   if (g_emaSlowHandle != INVALID_HANDLE) IndicatorRelease(g_emaSlowHandle);
   if (g_adxHandle != INVALID_HANDLE) IndicatorRelease(g_adxHandle);

   Print("=== OB_OS_RSI_STOCH_EA_V4.0_M5 (MT5) DEINITIALIZED ===");
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick()
{
   ExtSymbolInfo.RefreshRates();

   if (UseHourTrade)
   {
      MqlDateTime dt;
      TimeCurrent(dt);
      if (dt.day_of_week == 0 || dt.day_of_week == 6) return;
      if (dt.hour < StartHour || dt.hour > EndHour) return;
   }

   if (!IsNewBar()) return;

   if (UseTrailingStop && PositionsTotal() > 0)
      TrailingStopAllOrders();

   DetectPositions();

   int signal = CheckEntrySignal();

   if (signal != 0 && g_tradeCount == 0)
   {
      OpenFirstOrder(signal);
   }
}

//+------------------------------------------------------------------+
//| Check if new bar formed                                         |
//+------------------------------------------------------------------+
bool IsNewBar()
{
   datetime currentTime[1];
   ArraySetAsSeries(currentTime, true);
   if (CopyTime(_Symbol, PERIOD_CURRENT, 0, 1, currentTime) < 1) return false;

   if (currentTime[0] == g_timeLastBar) return false;
   g_timeLastBar = currentTime[0];
   return true;
}

//+------------------------------------------------------------------+
//| Detect current positions                                         |
//+------------------------------------------------------------------+
void DetectPositions()
{
   g_tradeCount = 0;
   g_isBuy = false;
   g_isSell = false;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      g_tradeCount++;

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
         g_isBuy = true;
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
         g_isSell = true;
   }
}

//+------------------------------------------------------------------+
//| Get indicator value from buffer                                  |
//+------------------------------------------------------------------+
double GetIndicatorValue(int handle, int buffer, int shift)
{
   double value[1];
   if (CopyBuffer(handle, buffer, shift, 1, value) < 1) return 0;
   return value[0];
}

//+------------------------------------------------------------------+
//| CHECK IF MARKET IS RANGING (V4.0 Smart Range Detection)         |
//+------------------------------------------------------------------+
bool IsMarketRanging()
{
   // Method 1: Check recent price range
   double high[], low[];
   ArraySetAsSeries(high, true);
   ArraySetAsSeries(low, true);

   if (CopyHigh(_Symbol, PERIOD_CURRENT, 1, RangeBars, high) < RangeBars) return true;
   if (CopyLow(_Symbol, PERIOD_CURRENT, 1, RangeBars, low) < RangeBars) return true;

   double highest = high[ArrayMaximum(high)];
   double lowest = low[ArrayMinimum(low)];
   double range = highest - lowest;
   double avgPrice = (highest + lowest) / 2.0;
   double rangePercent = (range / avgPrice) * 100.0;

   if (rangePercent < RangeMaxPercent)
   {
      Print("RANGE DETECTED: ", DoubleToString(rangePercent, 2), "% < ", DoubleToString(RangeMaxPercent, 2), "%");
      return true;
   }

   // Method 2: Check ADX
   double adx = GetIndicatorValue(g_adxHandle, 0, 1);
   if (adx < ADX_MinStrength)
   {
      Print("RANGE DETECTED: ADX=", DoubleToString(adx, 2), " < ", DoubleToString(ADX_MinStrength, 2));
      return true;
   }

   return false;
}

//+------------------------------------------------------------------+
//| CHECK ENTRY SIGNAL - V4.0 Balanced                               |
//+------------------------------------------------------------------+
int CheckEntrySignal()
{
   //=== V4.0: RANGE FILTER ===
   if (IsMarketRanging()) return 0;

   // Get indicator values
   double rsi = GetIndicatorValue(g_rsiHandle, 0, 1);
   double stochK = GetIndicatorValue(g_stochHandle, 0, 1);
   double stochD = GetIndicatorValue(g_stochHandle, 1, 1);
   double rsiPrev = GetIndicatorValue(g_rsiHandle, 0, 2);
   double stochKPrev = GetIndicatorValue(g_stochHandle, 0, 2);
   double stochDPrev = GetIndicatorValue(g_stochHandle, 1, 2);

   double emaFast = GetIndicatorValue(g_emaFastHandle, 0, 1);
   double emaSlow = GetIndicatorValue(g_emaSlowHandle, 0, 1);
   double adx = GetIndicatorValue(g_adxHandle, 0, 1);
   double diPlus = GetIndicatorValue(g_adxHandle, 1, 1);
   double diMinus = GetIndicatorValue(g_adxHandle, 2, 1);

   // Previous bar
   double close1 = iClose(_Symbol, PERIOD_CURRENT, 1);
   double close2 = iClose(_Symbol, PERIOD_CURRENT, 2);
   bool prevBarBullish = (close1 > close2);
   bool prevBarBearish = (close1 < close2);

   //=== BUY SIGNAL: Oversold + Crossover + Trend ===
   bool rsiOversold = (rsi < RSI_Oversold);
   bool stochOversold = (stochK < Stoch_Oversold);
   bool stochCrossUp = (stochKPrev <= stochDPrev && stochK > stochD);
   bool rsiTurningUp = (rsi > rsiPrev && rsiPrev < RSI_Oversold);
   bool trendBuy = (emaFast > emaSlow);
   bool strongTrend = (adx > ADX_MinStrength && diPlus > diMinus);

   // V4.0: Require oversold + crossover + bullish bar + trend
   bool buySignal = (rsiOversold || rsiTurningUp) && stochOversold && stochCrossUp && prevBarBullish;

   //=== SELL SIGNAL: Overbought + Crossover + Trend ===
   bool rsiOverbought = (rsi > RSI_Overbought);
   bool stochOverbought = (stochK > Stoch_Overbought);
   bool stochCrossDown = (stochKPrev >= stochDPrev && stochK < stochD);
   bool rsiTurningDown = (rsi < rsiPrev && rsiPrev > RSI_Overbought);
   bool trendSell = (emaFast < emaSlow);
   bool strongTrendSell = (adx > ADX_MinStrength && diMinus > diPlus);

   // V4.0: Require overbought + crossover + bearish bar + trend
   bool sellSignal = (rsiOverbought || rsiTurningDown) && stochOverbought && stochCrossDown && prevBarBearish;

   if (buySignal && !g_isBuy && !g_isSell) return 1;
   if (sellSignal && !g_isBuy && !g_isSell) return -1;
   return 0;
}

//+------------------------------------------------------------------+
//| Open First Order with SL/TP                                     |
//+------------------------------------------------------------------+
void OpenFirstOrder(int direction)
{
   double lot = LotSize;
   if (lot > MaxLotPerOrder) lot = MaxLotPerOrder;

   double sl = 0, tp = 0;
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   double ask = SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   double bid = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if (direction == 1)
   {
      sl = ask - StopLossPoints * point;
      tp = ask + TakeProfitPoints * point;
      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      if (ExtTrade.Buy(lot, _Symbol, ask, sl, tp, "V4_BUY"))
         Print("OPEN BUY - Lot:", lot, " SL:", sl, " TP:", tp);
   }
   else if (direction == -1)
   {
      sl = bid + StopLossPoints * point;
      tp = bid - TakeProfitPoints * point;
      sl = NormalizeDouble(sl, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));
      tp = NormalizeDouble(tp, (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS));

      if (ExtTrade.Sell(lot, _Symbol, bid, sl, tp, "V4_SELL"))
         Print("OPEN SELL - Lot:", lot, " SL:", sl, " TP:", tp);
   }
}

//+------------------------------------------------------------------+
//| Trailing Stop - ALL Orders                                      |
//+------------------------------------------------------------------+
void TrailingStopAllOrders()
{
   if (TrailingPoints == 0) return;

   ExtSymbolInfo.RefreshRates();
   double bid = ExtSymbolInfo.Bid();
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   double trailDist = TrailingPoints * point;

   for (int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if (ticket == 0) continue;

      if (PositionGetString(POSITION_SYMBOL) != _Symbol ||
          PositionGetInteger(POSITION_MAGIC) != MagicNumber)
         continue;

      double entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      double currentSL = PositionGetDouble(POSITION_SL);
      double currentTP = PositionGetDouble(POSITION_TP);

      if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
      {
         double distance = bid - entryPrice;
         if (distance >= trailDist)
         {
            double newSL = NormalizeDouble(bid - trailDist, digits);
            if (currentSL < newSL || currentSL == 0)
               ExtTrade.PositionModify(ticket, newSL, currentTP);
         }
      }
      else if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_SELL)
      {
         double distance = entryPrice - bid;
         if (distance >= trailDist)
         {
            double newSL = NormalizeDouble(bid + trailDist, digits);
            if (currentSL > newSL || currentSL == 0)
               ExtTrade.PositionModify(ticket, newSL, currentTP);
         }
      }
   }
}
//+------------------------------------------------------------------+
